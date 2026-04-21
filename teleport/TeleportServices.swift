import AppKit
import Combine
import Foundation
import SystemConfiguration

struct ConnectionLinkParser {
    func parse(_ rawLink: String) throws -> ConnectionConfiguration {
        let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased() else {
            throw ConfigurationError.invalidScheme
        }

        switch scheme {
        case ConnectionProtocolType.vless.rawValue:
            return try parseVLESS(trimmed, components: components)
        case ConnectionProtocolType.trojan.rawValue:
            return try parseTrojan(trimmed, components: components)
        default:
            throw ConfigurationError.invalidScheme
        }
    }

    private func parseVLESS(_ rawLink: String, components: URLComponents) throws -> ConnectionConfiguration {
        let base = try parseBase(rawLink, components: components)

        guard let user = components.user, !user.isEmpty else {
            throw ConfigurationError.missingUser
        }

        guard UUID(uuidString: user) != nil else {
            throw ConfigurationError.invalidUUID
        }

        let query = try queryDictionary(from: components)
        let securityRaw = (query["security"] ?? ConnectionSecurity.tls.rawValue).lowercased()
        guard let security = ConnectionSecurity(rawValue: securityRaw) else {
            throw ConfigurationError.unsupportedSecurity(securityRaw)
        }

        switch security {
        case .none, .tls:
            break
        case .reality:
            guard !(query["pbk"] ?? "").isEmpty else {
                throw ConfigurationError.missingParameter("pbk")
            }
            guard !(query["sni"] ?? "").isEmpty else {
                throw ConfigurationError.missingParameter("sni")
            }
        }

        let transport = try parseTransport(query: query)
        let flow = query["flow"]?.lowercased()
        if let flow, !flow.isEmpty {
            guard flow == "xtls-rprx-vision", security == .reality, transport == .tcp else {
                throw ConfigurationError.unsupportedFlow(flow)
            }
        }

        return ConnectionConfiguration(
            rawLink: rawLink,
            protocolType: .vless,
            host: base.host,
            port: base.port,
            remarks: base.remarks,
            security: security,
            transport: transport,
            path: query["path"],
            hostHeader: query["host"],
            serverName: query["sni"],
            alpn: parseALPN(query: query),
            fingerprint: query["fp"],
            publicKey: query["pbk"],
            shortID: query["sid"],
            spiderX: query["spx"],
            vlessUserID: user,
            vlessFlow: flow,
            trojanPassword: nil
        )
    }

    private func parseTrojan(_ rawLink: String, components: URLComponents) throws -> ConnectionConfiguration {
        let base = try parseBase(rawLink, components: components)
        let query = try queryDictionary(from: components)

        guard let password = components.user?.removingPercentEncoding, !password.isEmpty else {
            throw ConfigurationError.missingPassword
        }

        let securityRaw = (query["security"] ?? ConnectionSecurity.tls.rawValue).lowercased()
        guard let security = ConnectionSecurity(rawValue: securityRaw) else {
            throw ConfigurationError.unsupportedSecurity(securityRaw)
        }

        let transport = try parseTransport(query: query)

        switch security {
        case .tls:
            guard transport == .tcp || transport == .ws else {
                throw ConfigurationError.unsupportedTransport(transport.rawValue)
            }
        case .reality:
            guard transport == .tcp else {
                throw ConfigurationError.unsupportedTransport(transport.rawValue)
            }
            guard !(query["pbk"] ?? "").isEmpty else {
                throw ConfigurationError.missingParameter("pbk")
            }
            guard !(query["sni"] ?? "").isEmpty else {
                throw ConfigurationError.missingParameter("sni")
            }
        case .none:
            throw ConfigurationError.unsupportedSecurity(securityRaw)
        }

        return ConnectionConfiguration(
            rawLink: rawLink,
            protocolType: .trojan,
            host: base.host,
            port: base.port,
            remarks: base.remarks,
            security: security,
            transport: transport,
            path: query["path"],
            hostHeader: query["host"],
            serverName: query["sni"] ?? base.host,
            alpn: parseALPN(query: query),
            fingerprint: query["fp"],
            publicKey: query["pbk"],
            shortID: query["sid"],
            spiderX: query["spx"],
            vlessUserID: nil,
            vlessFlow: nil,
            trojanPassword: password
        )
    }

    private func parseBase(_ rawLink: String, components: URLComponents) throws -> (host: String, port: Int, remarks: String?) {
        guard let host = components.host, !host.isEmpty else {
            throw ConfigurationError.missingHost
        }

        guard let port = components.port else {
            throw ConfigurationError.invalidPort
        }

        let remarks = components.fragment?.removingPercentEncoding
        _ = rawLink
        return (host, port, remarks)
    }

    private func queryDictionary(from components: URLComponents) throws -> [String: String] {
        guard let queryItems = components.queryItems else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
    }

    private func parseTransport(query: [String: String]) throws -> ConnectionTransport {
        let transportRaw = (query["type"] ?? ConnectionTransport.tcp.rawValue).lowercased()
        guard let transport = ConnectionTransport(rawValue: transportRaw) else {
            throw ConfigurationError.unsupportedTransport(transportRaw)
        }
        return transport
    }

    private func parseALPN(query: [String: String]) -> [String] {
        query["alpn"]?.split(separator: ",").map { String($0) } ?? []
    }
}

final class ConfigurationStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = baseURL.appendingPathComponent("teleport", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("state.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else {
            return AppSnapshot(persistedConfiguration: nil, proxyEndpoint: .default)
        }

        if let snapshot = try? decoder.decode(AppSnapshot.self, from: data) {
            return snapshot
        }

        if let legacySnapshot = try? decoder.decode(LegacyAppSnapshot.self, from: data) {
            return legacySnapshot.asAppSnapshot
        }

        return AppSnapshot(persistedConfiguration: nil, proxyEndpoint: .default)
    }

    func save(_ snapshot: AppSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct XrayConfigurationWriter {
    let proxyEndpoint: ProxyEndpoint

    func writeConfig(for configuration: ConnectionConfiguration) throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("teleport", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let output = directory.appendingPathComponent("xray-config.json")
        let payload = makePayload(configuration: configuration)
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
        return output
    }

    private func makePayload(configuration: ConnectionConfiguration) -> [String: Any] {
        let streamSettings = makeStreamSettings(configuration: configuration)

        return [
            "log": [
                "loglevel": "warning"
            ],
            "inbounds": [
                [
                    "tag": "socks-in",
                    "listen": proxyEndpoint.host,
                    "port": proxyEndpoint.socksPort,
                    "protocol": "socks",
                    "settings": ["udp": true]
                ],
                [
                    "tag": "http-in",
                    "listen": proxyEndpoint.host,
                    "port": proxyEndpoint.httpPort,
                    "protocol": "http",
                    "settings": [:]
                ]
            ],
            "outbounds": [
                [
                    "tag": "proxy",
                    "protocol": configuration.protocolType.rawValue,
                    "settings": makeOutboundSettings(configuration: configuration),
                    "streamSettings": streamSettings
                ],
                [
                    "tag": "direct",
                    "protocol": "freedom",
                    "settings": [:]
                ]
            ],
            "routing": [
                "domainStrategy": "AsIs",
                "rules": [
                    [
                        "type": "field",
                        "outboundTag": "proxy",
                        "network": "tcp,udp"
                    ]
                ]
            ]
        ]
    }

    private func makeOutboundSettings(configuration: ConnectionConfiguration) -> [String: Any] {
        switch configuration.protocolType {
        case .vless:
            var user: [String: Any] = [
                "id": configuration.vlessUserID ?? "",
                "encryption": "none"
            ]

            if let flow = configuration.vlessFlow, !flow.isEmpty {
                user["flow"] = flow
            }

            return [
                "vnext": [[
                    "address": configuration.host,
                    "port": configuration.port,
                    "users": [user]
                ]]
            ]

        case .trojan:
            return [
                "servers": [[
                    "address": configuration.host,
                    "port": configuration.port,
                    "password": configuration.trojanPassword ?? ""
                ]]
            ]
        }
    }

    private func makeStreamSettings(configuration: ConnectionConfiguration) -> [String: Any] {
        var streamSettings: [String: Any] = [
            "network": configuration.transport.rawValue,
            "security": configuration.security.rawValue
        ]

        if configuration.transport == .ws {
            var wsSettings: [String: Any] = [
                "path": configuration.path ?? "/"
            ]

            if let hostHeader = configuration.hostHeader, !hostHeader.isEmpty {
                wsSettings["headers"] = ["Host": hostHeader]
            }

            streamSettings["wsSettings"] = wsSettings
        }

        if configuration.security == .tls {
            var tlsSettings: [String: Any] = [
                "serverName": configuration.serverName ?? configuration.host
            ]

            if !configuration.alpn.isEmpty {
                tlsSettings["alpn"] = configuration.alpn
            }

            streamSettings["tlsSettings"] = tlsSettings
        }

        if configuration.security == .reality {
            streamSettings["realitySettings"] = [
                "serverName": configuration.serverName ?? configuration.host,
                "fingerprint": configuration.fingerprint ?? "chrome",
                "publicKey": configuration.publicKey ?? "",
                "shortId": configuration.shortID ?? "",
                "spiderX": configuration.spiderX ?? ""
            ]
        }

        return streamSettings
    }
}

final class XrayRuntimeManager {
    private var process: Process?
    private var errorPipe: Pipe?
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func runtimeURL() -> URL? {
        bundle.url(forResource: "xray", withExtension: nil)
    }

    func start(configURL: URL) throws {
        guard process?.isRunning != true else { return }
        guard let runtimeURL = runtimeURL() else {
            throw RuntimeError.binaryNotFound
        }

        let process = Process()
        process.executableURL = runtimeURL
        process.arguments = ["run", "-c", configURL.path]

        let environment = ProcessInfo.processInfo.environment.merging([
            "XRAY_LOCATION_ASSET": assetDirectoryURL()?.path ?? ""
        ]) { _, new in new }
        process.environment = environment

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        errorPipe = pipe

        try process.run()
        self.process = process
    }

    func stop() {
        process?.terminate()
        process = nil
        errorPipe = nil
    }

    func capturedErrorOutput() -> String? {
        guard let pipe = errorPipe else { return nil }
        let data = pipe.fileHandleForReading.availableData
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func assetDirectoryURL() -> URL? {
        bundle.url(forResource: "xray-assets", withExtension: nil)
    }

    enum RuntimeError: LocalizedError {
        case binaryNotFound

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "Bundled Xray binary was not found in the app resources."
            }
        }
    }
}

final class SystemProxyService {
    private let processRunner: (Process) throws -> Void

    init(processRunner: @escaping (Process) throws -> Void = { try $0.run() }) {
        self.processRunner = processRunner
    }

    func enableProxy(endpoint: ProxyEndpoint) throws {
        try setWebProxy(enabled: true, host: endpoint.host, port: endpoint.httpPort)
        try setSecureWebProxy(enabled: true, host: endpoint.host, port: endpoint.httpPort)
        try setSOCKSProxy(enabled: true, host: endpoint.host, port: endpoint.socksPort)
    }

    func disableProxy() throws {
        try setWebProxy(enabled: false, host: nil, port: nil)
        try setSecureWebProxy(enabled: false, host: nil, port: nil)
        try setSOCKSProxy(enabled: false, host: nil, port: nil)
    }

    private func activeNetworkServices() throws -> [String] {
        let result = try runNetworkSetup(arguments: ["-listallnetworkservices"])

        return result.standardOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("An asterisk") }
            .filter { !$0.hasPrefix("*") }
    }

    private func setWebProxy(enabled: Bool, host: String?, port: Int?) throws {
        for service in try activeNetworkServices() {
            try runNetworkSetup(arguments: ["-setwebproxy", service, host ?? "", port.map(String.init) ?? "0"])
            try runNetworkSetup(arguments: ["-setwebproxystate", service, enabled ? "on" : "off"])
        }
    }

    private func setSecureWebProxy(enabled: Bool, host: String?, port: Int?) throws {
        for service in try activeNetworkServices() {
            try runNetworkSetup(arguments: ["-setsecurewebproxy", service, host ?? "", port.map(String.init) ?? "0"])
            try runNetworkSetup(arguments: ["-setsecurewebproxystate", service, enabled ? "on" : "off"])
        }
    }

    private func setSOCKSProxy(enabled: Bool, host: String?, port: Int?) throws {
        for service in try activeNetworkServices() {
            try runNetworkSetup(arguments: ["-setsocksfirewallproxy", service, host ?? "", port.map(String.init) ?? "0"])
            try runNetworkSetup(arguments: ["-setsocksfirewallproxystate", service, enabled ? "on" : "off"])
        }
    }

    @discardableResult
    private func runNetworkSetup(arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try processRunner(process)
        process.waitUntilExit()

        let stdout = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw ProxyError.commandFailed(arguments: arguments, standardError: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return CommandResult(standardOutput: stdout, standardError: stderr)
    }

    struct CommandResult {
        let standardOutput: String
        let standardError: String
    }

    enum ProxyError: LocalizedError {
        case commandFailed(arguments: [String], standardError: String)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(arguments, standardError):
                let command = arguments.joined(separator: " ")
                if standardError.isEmpty {
                    return "Failed to update system proxy with command: \(command)"
                }
                return "Failed to update system proxy with command: \(command)\n\(standardError)"
            }
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var draftLink: String = ""
    @Published private(set) var savedConfiguration: ConnectionConfiguration?
    @Published private(set) var connectionPhase: ConnectionPhase = .unconfigured
    @Published private(set) var proxyPhase: ProxyPhase = .disabled
    @Published private(set) var lastError: String?
    @Published private(set) var proxyEndpoint: ProxyEndpoint

    private let parser: ConnectionLinkParser
    private let store: ConfigurationStore
    private let runtimeManager: XrayRuntimeManager
    private let proxyService: SystemProxyService

    convenience init() {
        self.init(
            parser: ConnectionLinkParser(),
            store: ConfigurationStore(),
            runtimeManager: XrayRuntimeManager(),
            proxyService: SystemProxyService()
        )
    }

    init(
        parser: ConnectionLinkParser,
        store: ConfigurationStore,
        runtimeManager: XrayRuntimeManager,
        proxyService: SystemProxyService
    ) {
        self.parser = parser
        self.store = store
        self.runtimeManager = runtimeManager
        self.proxyService = proxyService

        let snapshot = store.load()
        self.proxyEndpoint = snapshot.proxyEndpoint

        if let rawLink = snapshot.persistedConfiguration?.configuration.rawLink,
           let reparsedConfiguration = try? parser.parse(rawLink) {
            self.savedConfiguration = reparsedConfiguration
            self.draftLink = rawLink
        } else {
            self.savedConfiguration = snapshot.persistedConfiguration?.configuration
            self.draftLink = snapshot.persistedConfiguration?.configuration.rawLink ?? ""
        }

        self.connectionPhase = savedConfiguration == nil ? .unconfigured : .stopped
    }

    var canStart: Bool {
        savedConfiguration != nil && connectionPhase != .running && connectionPhase != .starting
    }

    var canStop: Bool {
        connectionPhase == .running || connectionPhase == .starting || connectionPhase == .failed
    }

    var canEnableProxy: Bool {
        connectionPhase == .running && proxyPhase != .enabled && proxyPhase != .enabling
    }

    var statusSummary: String {
        switch connectionPhase {
        case .unconfigured:
            return "Add a connection link to get started"
        case .ready, .stopped:
            return "Ready to start Xray"
        case .starting:
            return "Starting Xray…"
        case .running:
            return "Xray is running"
        case .stopping:
            return "Stopping Xray…"
        case .failed:
            return lastError ?? "Xray failed"
        }
    }

    func saveLink() {
        do {
            let configuration = try parser.parse(draftLink)
            savedConfiguration = configuration
            connectionPhase = .stopped
            lastError = nil
            try persist()
        } catch {
            lastError = error.localizedDescription
            connectionPhase = .unconfigured
        }
    }

    func clearError() {
        lastError = nil
    }

    func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            draftLink = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func startConnection() {
        guard let savedConfiguration else {
            connectionPhase = .unconfigured
            lastError = "Save a connection link first"
            return
        }

        connectionPhase = .starting
        lastError = nil

        do {
            let configURL = try XrayConfigurationWriter(proxyEndpoint: proxyEndpoint).writeConfig(for: savedConfiguration)
            try runtimeManager.start(configURL: configURL)
            connectionPhase = .running
        } catch {
            connectionPhase = .failed
            lastError = error.localizedDescription
        }
    }

    func stopConnection() {
        connectionPhase = .stopping
        runtimeManager.stop()
        connectionPhase = savedConfiguration == nil ? .unconfigured : .stopped
    }

    func enableProxy() {
        guard connectionPhase == .running else {
            proxyPhase = .failed
            lastError = "Proxy cannot be enabled until Xray is running"
            return
        }

        proxyPhase = .enabling
        do {
            try proxyService.enableProxy(endpoint: proxyEndpoint)
            proxyPhase = .enabled
            lastError = nil
        } catch {
            proxyPhase = .failed
            lastError = error.localizedDescription
        }
    }

    func disableProxy() {
        proxyPhase = .disabling
        do {
            try proxyService.disableProxy()
            proxyPhase = .disabled
            lastError = nil
        } catch {
            proxyPhase = .failed
            lastError = error.localizedDescription
        }
    }

    private func persist() throws {
        let snapshot = AppSnapshot(
            persistedConfiguration: savedConfiguration.map { PersistedConfiguration(configuration: $0, savedAt: Date()) },
            proxyEndpoint: proxyEndpoint
        )
        try store.save(snapshot)
    }
}
