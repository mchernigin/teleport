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
            return AppSnapshot(savedConnections: [], selectedConnectionID: nil, proxyEndpoint: .default)
        }

        if let snapshot = try? decoder.decode(AppSnapshot.self, from: data) {
            return snapshot
        }

        if let legacySnapshot = try? decoder.decode(LegacyAppSnapshot.self, from: data) {
            let migratedSnapshot = legacySnapshot.asAppSnapshot
            try? save(migratedSnapshot)
            return migratedSnapshot
        }

        return AppSnapshot(savedConnections: [], selectedConnectionID: nil, proxyEndpoint: .default)
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
    @Published private(set) var savedConnections: [SavedConnection]
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var connectionPhase: ConnectionPhase = .unconfigured
    @Published private(set) var proxyPhase: ProxyPhase = .disabled
    @Published private(set) var lastError: String?
    @Published private(set) var proxyEndpoint: ProxyEndpoint

    private let parser: ConnectionLinkParser
    private let store: ConfigurationStore
    private let runtimeManager: XrayRuntimeManager
    private let proxyService: SystemProxyService
    private let operationQueue = DispatchQueue(label: "dev.x.teleport.connection-operations", qos: .userInitiated)

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

        let normalizedConnections = snapshot.savedConnections.map { savedConnection in
            if let reparsedConfiguration = try? parser.parse(savedConnection.configuration.rawLink) {
                return SavedConnection(id: savedConnection.id, configuration: reparsedConfiguration, savedAt: savedConnection.savedAt)
            }
            return savedConnection
        }

        self.savedConnections = normalizedConnections
        self.selectedConnectionID = snapshot.selectedConnectionID ?? normalizedConnections.first?.id
        self.draftLink = ""
        self.connectionPhase = normalizedConnections.isEmpty ? .unconfigured : .stopped
    }

    var selectedConnection: SavedConnection? {
        guard let selectedConnectionID else { return savedConnections.first }
        return savedConnections.first { $0.id == selectedConnectionID } ?? savedConnections.first
    }

    var selectedConfiguration: ConnectionConfiguration? {
        selectedConnection?.configuration
    }

    var canConnect: Bool {
        selectedConfiguration != nil && connectionPhase != .starting && connectionPhase != .running && proxyPhase != .enabling && proxyPhase != .enabled
    }

    var canDisconnect: Bool {
        connectionPhase == .running || connectionPhase == .starting || proxyPhase == .enabled || proxyPhase == .enabling || connectionPhase == .failed
    }

    var canChangeSelection: Bool {
        !(connectionPhase == .running || connectionPhase == .starting || connectionPhase == .stopping || proxyPhase == .enabled || proxyPhase == .enabling || proxyPhase == .disabling)
    }

    var isConnected: Bool {
        connectionPhase == .running && proxyPhase == .enabled
    }

    var statusSummary: String {
        switch connectionPhase {
        case .unconfigured:
            return savedConnections.isEmpty ? "Add a connection in Settings to get started" : "Select a connection to get started"
        case .ready, .stopped:
            return proxyPhase == .enabled ? "Connected" : "Disconnected"
        case .starting:
            return proxyPhase == .enabling ? "Connecting…" : "Starting connection…"
        case .running:
            return proxyPhase == .enabled ? "Connected" : "Xray is ready"
        case .stopping:
            return "Disconnecting…"
        case .failed:
            return lastError ?? "Connection failed"
        }
    }

    func addConnection() {
        do {
            let configuration = try parser.parse(draftLink)
            let savedConnection = SavedConnection(id: UUID(), configuration: configuration, savedAt: Date())
            savedConnections.append(savedConnection)
            selectedConnectionID = savedConnection.id
            draftLink = ""
            connectionPhase = .stopped
            lastError = nil
            try persist()
        } catch {
            lastError = error.localizedDescription
            if savedConnections.isEmpty {
                connectionPhase = .unconfigured
            }
        }
    }

    func removeConnection(id: UUID) {
        guard let index = savedConnections.firstIndex(where: { $0.id == id }) else { return }

        if !canChangeSelection && selectedConnectionID == id {
            lastError = "Disconnect before removing the active connection"
            return
        }

        savedConnections.remove(at: index)

        if selectedConnectionID == id {
            selectedConnectionID = savedConnections.indices.contains(index) ? savedConnections[index].id : savedConnections.last?.id
        }

        if savedConnections.isEmpty {
            selectedConnectionID = nil
            connectionPhase = .unconfigured
        }

        persistSettingError()
    }

    func selectConnection(id: UUID) {
        if !canChangeSelection, selectedConnectionID != id {
            lastError = "Disconnect before switching connections"
            return
        }

        selectedConnectionID = id
        if selectedConfiguration != nil, connectionPhase == .unconfigured {
            connectionPhase = .stopped
        }
        lastError = nil
        persistSettingError()
    }

    func clearError() {
        lastError = nil
    }

    func pasteFromClipboard() {
        if let value = NSPasteboard.general.string(forType: .string) {
            draftLink = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func connect() {
        guard let selectedConfiguration else {
            connectionPhase = .unconfigured
            lastError = "Add and select a connection first"
            return
        }

        let proxyEndpoint = proxyEndpoint
        let runtimeManager = runtimeManager
        let proxyService = proxyService

        connectionPhase = .starting
        proxyPhase = .enabling
        lastError = nil

        operationQueue.async { [weak self] in
            do {
                let configURL = try XrayConfigurationWriter(proxyEndpoint: proxyEndpoint).writeConfig(for: selectedConfiguration)
                try runtimeManager.start(configURL: configURL)
                try proxyService.enableProxy(endpoint: proxyEndpoint)

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .running
                    self?.proxyPhase = .enabled
                    self?.lastError = nil
                }
            } catch {
                runtimeManager.stop()

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .failed
                    self?.proxyPhase = .failed
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func disconnect() {
        let shouldDisableProxy = proxyPhase == .enabled || proxyPhase == .enabling || proxyPhase == .failed || proxyPhase == .disabling
        let hasSavedConfiguration = selectedConfiguration != nil
        let runtimeManager = runtimeManager
        let proxyService = proxyService

        connectionPhase = .stopping
        proxyPhase = .disabling

        operationQueue.async { [weak self] in
            if shouldDisableProxy {
                do {
                    try proxyService.disableProxy()
                    Task { @MainActor [weak self] in
                        self?.proxyPhase = .disabled
                        self?.lastError = nil
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.proxyPhase = .failed
                        self?.lastError = error.localizedDescription
                    }
                }
            }

            runtimeManager.stop()

            Task { @MainActor [weak self] in
                self?.connectionPhase = hasSavedConfiguration ? .stopped : .unconfigured
                if !shouldDisableProxy {
                    self?.proxyPhase = .disabled
                    self?.lastError = nil
                }
            }
        }
    }

    func handleAppTermination() {
        teardownConnection(resetError: true)
    }

    private func teardownConnection(resetError: Bool) {
        let shouldDisableProxy = proxyPhase == .enabled || proxyPhase == .enabling || proxyPhase == .failed || proxyPhase == .disabling

        if shouldDisableProxy {
            do {
                try proxyService.disableProxy()
                Task { @MainActor [weak self] in
                    self?.proxyPhase = .disabled
                    if resetError {
                        self?.lastError = nil
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.proxyPhase = .failed
                    if !resetError {
                        self?.lastError = error.localizedDescription
                    }
                }
            }
        }

        runtimeManager.stop()

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.connectionPhase = self.selectedConfiguration == nil ? .unconfigured : .stopped
            if !shouldDisableProxy {
                self.proxyPhase = .disabled
                if resetError {
                    self.lastError = nil
                }
            }
        }
    }

    private func persistSettingError() {
        do {
            try persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist() throws {
        let snapshot = AppSnapshot(
            savedConnections: savedConnections,
            selectedConnectionID: selectedConnectionID ?? savedConnections.first?.id,
            proxyEndpoint: proxyEndpoint
        )
        try store.save(snapshot)
    }
}
