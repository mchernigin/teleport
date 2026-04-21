import Foundation

@main
struct VerifyCore {
    static func main() throws {
        try testValidVLESSParsingAndConfigGeneration()
        try testValidTrojanParsingAndConfigGeneration()
        try testValidTrojanRealityParsingAndConfigGeneration()
        try testMalformedAndUnsupportedLinks()
        try testLegacyStateMigration()
        try testRuntimeStartupFailureWithoutBundledBinary()
        try testProxyEnablementBlockedBeforeRuntimeReady()
        print("verify_core: all checks passed")
    }

    private static func testValidVLESSParsingAndConfigGeneration() throws {
        let parser = ConnectionLinkParser()
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=ws&sni=example.com&path=%2Fws&alpn=h2,http%2F1.1#Demo"
        let configuration = try parser.parse(link)

        precondition(configuration.protocolType == .vless)
        precondition(configuration.host == "example.com")
        precondition(configuration.port == 443)
        precondition(configuration.transport == .ws)
        precondition(configuration.security == .tls)
        precondition(configuration.vlessUserID == "123e4567-e89b-12d3-a456-426614174000")

        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: configuration)
        let content = try String(contentsOf: configURL, encoding: .utf8)
        precondition(content.contains("\"protocol\" : \"vless\""))
        precondition(content.contains("example.com"))
        precondition(content.contains("wsSettings"))

        let realityLink = "vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=abc123abc123abc123abc123abc123abc123abc123&sid=a1b2c3d4&type=tcp#Reality"
        let realityConfiguration = try parser.parse(realityLink)
        precondition(realityConfiguration.vlessFlow == "xtls-rprx-vision")

        let realityConfigURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: realityConfiguration)
        let realityContent = try String(contentsOf: realityConfigURL, encoding: .utf8)
        precondition(realityContent.contains("xtls-rprx-vision"))
    }

    private static func testValidTrojanParsingAndConfigGeneration() throws {
        let parser = ConnectionLinkParser()
        let link = "trojan://secret-password@example.com:443?security=tls&type=ws&sni=example.com&host=cdn.example.com&path=%2Fsocket#Trojan"
        let configuration = try parser.parse(link)

        precondition(configuration.protocolType == .trojan)
        precondition(configuration.host == "example.com")
        precondition(configuration.port == 443)
        precondition(configuration.transport == .ws)
        precondition(configuration.security == .tls)
        precondition(configuration.trojanPassword == "secret-password")
        precondition(configuration.hostHeader == "cdn.example.com")

        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: configuration)
        let content = try String(contentsOf: configURL, encoding: .utf8)
        precondition(content.contains("\"protocol\" : \"trojan\""))
        precondition(content.contains("secret-password"))
        precondition(content.contains("cdn.example.com"))
        precondition(content.contains("wsSettings"))
    }

    private static func testValidTrojanRealityParsingAndConfigGeneration() throws {
        let parser = ConnectionLinkParser()
        let link = "trojan://secret-password@example.com:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=abc123abc123abc123abc123abc123abc123abc123&sid=a1b2c3d4#TrojanReality"
        let configuration = try parser.parse(link)

        precondition(configuration.protocolType == .trojan)
        precondition(configuration.security == .reality)
        precondition(configuration.transport == .tcp)
        precondition(configuration.serverName == "www.microsoft.com")
        precondition(configuration.publicKey == "abc123abc123abc123abc123abc123abc123abc123")
        precondition(configuration.shortID == "a1b2c3d4")

        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: configuration)
        let content = try String(contentsOf: configURL, encoding: .utf8)
        precondition(content.contains("\"protocol\" : \"trojan\""))
        precondition(content.contains("\"security\" : \"reality\""))
        precondition(content.contains("realitySettings"))
        precondition(content.contains("abc123abc123abc123abc123abc123abc123abc123"))
    }

    private static func testMalformedAndUnsupportedLinks() throws {
        let parser = ConnectionLinkParser()

        do {
            _ = try parser.parse("https://example.com")
            fatalError("Expected invalidScheme")
        } catch let error as ConfigurationError {
            precondition(error == .invalidScheme)
        }

        do {
            _ = try parser.parse("vless://not-a-uuid@example.com:443?security=tls&type=tcp")
            fatalError("Expected invalidUUID")
        } catch let error as ConfigurationError {
            precondition(error == .invalidUUID)
        }

        do {
            _ = try parser.parse("vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=grpc")
            fatalError("Expected unsupportedTransport")
        } catch let error as ConfigurationError {
            if case .unsupportedTransport("grpc") = error {
            } else {
                fatalError("Unexpected error: \(error)")
            }
        }

        do {
            _ = try parser.parse("vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=reality&type=tcp")
            fatalError("Expected missingParameter")
        } catch let error as ConfigurationError {
            if case .missingParameter("pbk") = error {
            } else {
                fatalError("Unexpected error: \(error)")
            }
        }

        do {
            _ = try parser.parse("vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=tcp&flow=xtls-rprx-vision")
            fatalError("Expected unsupportedFlow")
        } catch let error as ConfigurationError {
            if case .unsupportedFlow("xtls-rprx-vision") = error {
            } else {
                fatalError("Unexpected error: \(error)")
            }
        }

        do {
            _ = try parser.parse("trojan://@example.com:443?security=tls&type=tcp")
            fatalError("Expected missingPassword")
        } catch let error as ConfigurationError {
            precondition(error == .missingPassword)
        }

        do {
            _ = try parser.parse("trojan://secret@example.com:443?security=reality&type=tcp")
            fatalError("Expected missingParameter")
        } catch let error as ConfigurationError {
            if case .missingParameter("pbk") = error {
            } else {
                fatalError("Unexpected error: \(error)")
            }
        }

        do {
            _ = try parser.parse("trojan://secret@example.com:443?security=reality&type=ws&sni=example.com&pbk=abc123")
            fatalError("Expected unsupportedTransport")
        } catch let error as ConfigurationError {
            if case .unsupportedTransport("ws") = error {
            } else {
                fatalError("Unexpected error: \(error)")
            }
        }
    }

    private static func testLegacyStateMigration() throws {
        let legacy = LegacyAppSnapshot(
            persistedConfiguration: LegacyPersistedConfiguration(
                configuration: LegacyVLESSConfiguration(
                    rawLink: "vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=tcp&sni=example.com#Legacy",
                    id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!,
                    userID: "123e4567-e89b-12d3-a456-426614174000",
                    host: "example.com",
                    port: 443,
                    remarks: "Legacy",
                    security: .tls,
                    transport: .tcp,
                    flow: nil,
                    path: nil,
                    serverName: "example.com",
                    alpn: [],
                    fingerprint: nil,
                    publicKey: nil,
                    shortID: nil,
                    spiderX: nil
                ),
                savedAt: Date(timeIntervalSince1970: 0)
            ),
            proxyEndpoint: .default
        )

        let migrated = legacy.asAppSnapshot
        precondition(migrated.persistedConfiguration?.configuration.protocolType == .vless)
        precondition(migrated.persistedConfiguration?.configuration.vlessUserID == "123e4567-e89b-12d3-a456-426614174000")
        precondition(migrated.persistedConfiguration?.configuration.rawLink.contains("vless://") == true)
    }

    private static func testRuntimeStartupFailureWithoutBundledBinary() throws {
        let parser = ConnectionLinkParser()
        let configuration = try parser.parse("vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=tcp&sni=example.com")
        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: configuration)
        let runtimeManager = XrayRuntimeManager(bundle: .main)

        do {
            try runtimeManager.start(configURL: configURL)
            fatalError("Expected binaryNotFound")
        } catch let error as XrayRuntimeManager.RuntimeError {
            switch error {
            case .binaryNotFound:
                break
            }
        }
    }

    @MainActor
    private static func testProxyEnablementBlockedBeforeRuntimeReady() throws {
        let viewModel = AppViewModel()
        viewModel.enableProxy()
        precondition(viewModel.proxyPhase == .failed)
        precondition(viewModel.lastError == "Proxy cannot be enabled until Xray is running")
    }
}
