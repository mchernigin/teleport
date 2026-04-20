import Foundation

@main
struct VerifyCore {
    static func main() throws {
        try testValidVLESSParsingAndConfigGeneration()
        try testMalformedAndUnsupportedLinks()
        try testRuntimeStartupFailureWithoutBundledBinary()
        try testProxyEnablementBlockedBeforeRuntimeReady()
        print("verify_core: all checks passed")
    }

    private static func testValidVLESSParsingAndConfigGeneration() throws {
        let parser = VLESSParser()
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=ws&sni=example.com&path=%2Fws&alpn=h2,http%2F1.1#Demo"
        let configuration = try parser.parse(link)

        precondition(configuration.host == "example.com")
        precondition(configuration.port == 443)
        precondition(configuration.transport == .ws)
        precondition(configuration.security == .tls)

        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: configuration)
        let content = try String(contentsOf: configURL, encoding: .utf8)
        precondition(content.contains("example.com"))
        precondition(content.contains("wsSettings"))
        precondition(content.contains("8080"))
        precondition(content.contains("1080"))

        let realityLink = "vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=abc123abc123abc123abc123abc123abc123abc123&sid=a1b2c3d4&type=tcp#Reality"
        let realityConfiguration = try parser.parse(realityLink)
        precondition(realityConfiguration.flow == "xtls-rprx-vision")

        let realityConfigURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeConfig(for: realityConfiguration)
        let realityContent = try String(contentsOf: realityConfigURL, encoding: .utf8)
        precondition(realityContent.contains("xtls-rprx-vision"))
    }

    private static func testMalformedAndUnsupportedLinks() throws {
        let parser = VLESSParser()

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
    }

    private static func testRuntimeStartupFailureWithoutBundledBinary() throws {
        let parser = VLESSParser()
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
