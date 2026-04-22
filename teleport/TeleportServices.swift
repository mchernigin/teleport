import AppKit
import Combine
import Foundation
import SystemConfiguration

struct ConnectionLinkParser {
    nonisolated func parse(_ rawLink: String) throws -> ConnectionConfiguration {
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

    nonisolated private func parseVLESS(_ rawLink: String, components: URLComponents) throws -> ConnectionConfiguration {
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
        if transport == .grpc {
            guard !(query["serviceName"] ?? "").isEmpty else {
                throw ConfigurationError.missingParameter("serviceName")
            }
        }

        let flow = query["flow"]?.lowercased()
        if let flow, !flow.isEmpty {
            let supportsVisionFlow = flow == "xtls-rprx-vision"
                && transport == .tcp
                && (security == .tls || security == .reality)
            guard supportsVisionFlow else {
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
            trojanPassword: nil,
            allowsInsecureTLS: parseAllowsInsecureTLS(query: query),
            grpcServiceName: query["serviceName"],
            transportMode: query["mode"]
        )
    }

    nonisolated private func parseTrojan(_ rawLink: String, components: URLComponents) throws -> ConnectionConfiguration {
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
            guard transport == .tcp || transport == .ws || transport == .grpc else {
                throw ConfigurationError.unsupportedTransport(transport.rawValue)
            }
            if transport == .grpc {
                guard !(query["serviceName"] ?? "").isEmpty else {
                    throw ConfigurationError.missingParameter("serviceName")
                }
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
            trojanPassword: password,
            allowsInsecureTLS: parseAllowsInsecureTLS(query: query),
            grpcServiceName: query["serviceName"],
            transportMode: query["mode"]
        )
    }

    nonisolated private func parseBase(_ rawLink: String, components: URLComponents) throws -> (host: String, port: Int, remarks: String?) {
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

    nonisolated private func queryDictionary(from components: URLComponents) throws -> [String: String] {
        guard let queryItems = components.queryItems else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") })
    }

    nonisolated private func parseTransport(query: [String: String]) throws -> ConnectionTransport {
        let transportRaw = (query["type"] ?? ConnectionTransport.tcp.rawValue).lowercased()
        guard let transport = ConnectionTransport(rawValue: transportRaw) else {
            throw ConfigurationError.unsupportedTransport(transportRaw)
        }
        return transport
    }

    nonisolated private func parseALPN(query: [String: String]) -> [String] {
        query["alpn"]?.split(separator: ",").map { String($0) } ?? []
    }

    nonisolated private func parseAllowsInsecureTLS(query: [String: String]) -> Bool {
        parseBooleanQueryValue(query["insecure"]) || parseBooleanQueryValue(query["allowInsecure"])
    }

    nonisolated private func parseBooleanQueryValue(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
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
            return AppSnapshot(savedConnections: [], subscriptionSources: [], selectedConnectionID: nil, proxyEndpoint: .default)
        }

        if let snapshot = try? decoder.decode(AppSnapshot.self, from: data) {
            return snapshot
        }

        if let legacySnapshot = try? decoder.decode(LegacyAppSnapshot.self, from: data) {
            let migratedSnapshot = legacySnapshot.asAppSnapshot
            try? save(migratedSnapshot)
            return migratedSnapshot
        }

        return AppSnapshot(savedConnections: [], subscriptionSources: [], selectedConnectionID: nil, proxyEndpoint: .default)
    }

    func save(_ snapshot: AppSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}

struct SubscriptionImportResult {
    let importedEntries: [ImportedSubscriptionEntry]
    let skippedCount: Int
}

struct ImportedSubscriptionEntry {
    let sourceEntryID: String
    let configuration: ConnectionConfiguration
}

struct SubscriptionReplacementResult {
    let savedConnections: [SavedConnection]
    let selectedConnectionID: UUID?
}

struct SubscriptionConnectionReconciler {
    func reconcile(
        existingConnections: [SavedConnection],
        sourceID: UUID,
        selectedConnectionID: UUID?,
        importedEntries: [ImportedSubscriptionEntry],
        fetchedAt: Date,
        autoSelectFirstImported: Bool
    ) -> SubscriptionReplacementResult {
        let previousSelectedConnection = existingConnections.first { $0.id == selectedConnectionID }
        let previousImportedEntries = existingConnections.filter { $0.source?.subscriptionSourceID == sourceID }

        let existingIDsByEntry: [String: UUID] = Dictionary(uniqueKeysWithValues: previousImportedEntries.compactMap { connection in
            guard let source = connection.source else { return nil }
            return (source.subscriptionEntryID, connection.id)
        })
        let existingSavedAtByEntry: [String: Date] = Dictionary(uniqueKeysWithValues: previousImportedEntries.compactMap { connection in
            guard let source = connection.source else { return nil }
            return (source.subscriptionEntryID, connection.savedAt)
        })
        let existingHealthByEntry: [String: ConnectionHealthCheck] = Dictionary(uniqueKeysWithValues: previousImportedEntries.compactMap { connection in
            guard let source = connection.source,
                  let healthCheck = connection.healthCheck else {
                return nil
            }
            return (source.subscriptionEntryID, healthCheck)
        })

        let replacementConnections = importedEntries.map { entry in
            SavedConnection(
                id: existingIDsByEntry[entry.sourceEntryID] ?? UUID(),
                configuration: entry.configuration,
                savedAt: existingSavedAtByEntry[entry.sourceEntryID] ?? fetchedAt,
                source: ConnectionSourceMetadata(subscriptionSourceID: sourceID, subscriptionEntryID: entry.sourceEntryID),
                healthCheck: existingHealthByEntry[entry.sourceEntryID]
            )
        }
        .sorted { lhs, rhs in
            lhs.configuration.displayName.localizedCaseInsensitiveCompare(rhs.configuration.displayName) == .orderedAscending
        }

        var updatedConnections = existingConnections.filter { $0.source?.subscriptionSourceID != sourceID }
        updatedConnections.append(contentsOf: replacementConnections)

        let resolvedSelectedConnectionID: UUID?
        if let previousSelectedConnection,
           previousSelectedConnection.source?.subscriptionSourceID == sourceID {
            let previousEntryID = previousSelectedConnection.source?.subscriptionEntryID
            if let previousEntryID,
               let matched = replacementConnections.first(where: { $0.source?.subscriptionEntryID == previousEntryID }) {
                resolvedSelectedConnectionID = matched.id
            } else if let firstReplacement = replacementConnections.first {
                resolvedSelectedConnectionID = firstReplacement.id
            } else {
                resolvedSelectedConnectionID = updatedConnections.first?.id
            }
        } else if autoSelectFirstImported,
                  selectedConnectionID == nil,
                  let firstReplacement = replacementConnections.first {
            resolvedSelectedConnectionID = firstReplacement.id
        } else if let selectedConnectionID,
                  updatedConnections.contains(where: { $0.id == selectedConnectionID }) {
            resolvedSelectedConnectionID = selectedConnectionID
        } else {
            resolvedSelectedConnectionID = updatedConnections.first?.id
        }

        return SubscriptionReplacementResult(
            savedConnections: updatedConnections,
            selectedConnectionID: resolvedSelectedConnectionID
        )
    }
}

struct SubscriptionClient {
    func fetchCandidateLinks(from url: URL) throws -> [String] {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let session = URLSession(configuration: .ephemeral)
        let semaphore = DispatchSemaphore(value: 0)

        var responseData: Data?
        var response: URLResponse?
        var responseError: Error?

        let task = session.dataTask(with: request) { data, urlResponse, error in
            responseData = data
            response = urlResponse
            responseError = error
            semaphore.signal()
        }

        task.resume()
        semaphore.wait()
        session.finishTasksAndInvalidate()

        if let responseError {
            throw SubscriptionError.networkFailure(responseError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw SubscriptionError.networkFailure("Subscription request failed with status \(httpResponse.statusCode)")
        }

        guard let responseData, !responseData.isEmpty else {
            throw SubscriptionError.emptyPayload
        }

        let rawText = String(decoding: responseData, as: UTF8.self)
        let directLinks = extractCandidateLinks(from: rawText)
        if !directLinks.isEmpty {
            return directLinks
        }

        let compactBase64 = rawText
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        if let decodedData = Data(base64Encoded: compactBase64, options: [.ignoreUnknownCharacters]) {
            let decodedText = String(decoding: decodedData, as: UTF8.self)
            let decodedLinks = extractCandidateLinks(from: decodedText)
            if !decodedLinks.isEmpty {
                return decodedLinks
            }
        }

        throw SubscriptionError.noSupportedEntries
    }

    private func extractCandidateLinks(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { value in
                let lowercased = value.lowercased()
                return lowercased.hasPrefix("vless://") || lowercased.hasPrefix("trojan://")
            }
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

        if configuration.transport == .grpc {
            streamSettings["grpcSettings"] = [
                "serviceName": configuration.grpcServiceName ?? ""
            ]
        }

        if configuration.transport == .xhttp {
            var xhttpSettings: [String: Any] = [
                "path": configuration.path ?? "/"
            ]

            if let hostHeader = configuration.hostHeader, !hostHeader.isEmpty {
                xhttpSettings["host"] = hostHeader
            }

            if let mode = configuration.transportMode, !mode.isEmpty {
                xhttpSettings["mode"] = mode
            }

            streamSettings["xhttpSettings"] = xhttpSettings
        }

        if configuration.security == .tls {
            var tlsSettings: [String: Any] = [
                "serverName": configuration.serverName ?? configuration.host
            ]

            if !configuration.alpn.isEmpty {
                tlsSettings["alpn"] = configuration.alpn
            }

            if configuration.allowsInsecureTLS {
                tlsSettings["allowInsecure"] = true
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

final class XrayRuntimeManager: @unchecked Sendable {
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

final class SystemProxyService: @unchecked Sendable {
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

struct ConnectionHealthProbeResult {
    let state: ConnectionHealthState
    let checkedAt: Date
    let latencyMilliseconds: Int?
    let failureSummary: String?
}

final class ConnectionHealthProbeService: @unchecked Sendable {
    private let attemptCount: Int
    private let tcpTimeoutSeconds: Int
    private let pingTimeoutMilliseconds: Int

    init(
        attemptCount: Int = 3,
        tcpTimeoutSeconds: Int = 3,
        pingTimeoutMilliseconds: Int = 1000
    ) {
        self.attemptCount = max(1, attemptCount)
        self.tcpTimeoutSeconds = max(1, tcpTimeoutSeconds)
        self.pingTimeoutMilliseconds = max(100, pingTimeoutMilliseconds)
    }

    func probe(_ connection: SavedConnection) async -> ConnectionHealthProbeResult {
        guard UInt16(exactly: connection.configuration.port) != nil else {
            return ConnectionHealthProbeResult(
                state: .unreachable,
                checkedAt: Date(),
                latencyMilliseconds: nil,
                failureSummary: "Invalid port"
            )
        }

        let checkedAt = Date()
        let availabilityResult = await tcpAvailabilityCheck(connection)

        guard availabilityResult.isReachable else {
            return ConnectionHealthProbeResult(
                state: .unreachable,
                checkedAt: checkedAt,
                latencyMilliseconds: nil,
                failureSummary: availabilityResult.failureSummary ?? "Unavailable"
            )
        }

        let pingLatencies = await pingSamples(host: connection.configuration.host)
        if !pingLatencies.isEmpty {
            return ConnectionHealthProbeResult(
                state: .reachable,
                checkedAt: checkedAt,
                latencyMilliseconds: Self.median(pingLatencies),
                failureSummary: nil
            )
        }

        return ConnectionHealthProbeResult(
            state: .reachable,
            checkedAt: checkedAt,
            latencyMilliseconds: nil,
            failureSummary: nil
        )
    }

    private func tcpAvailabilityCheck(_ connection: SavedConnection) async -> (isReachable: Bool, failureSummary: String?) {
        do {
            let result = try await runCommand(
                executable: "/usr/bin/nc",
                arguments: ["-z", "-G", String(tcpTimeoutSeconds), connection.configuration.host, String(connection.configuration.port)]
            )
            return (result.terminationStatus == 0, result.terminationStatus == 0 ? nil : summarizedNetcatFailure(result.standardError))
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func pingSamples(host: String) async -> [Int] {
        do {
            let result = try await runCommand(
                executable: "/sbin/ping",
                arguments: ["-c", String(attemptCount), "-W", String(pingTimeoutMilliseconds), host]
            )
            guard result.terminationStatus == 0 || result.terminationStatus == 2 else {
                return []
            }
            return parsePingLatencies(result.standardOutput)
        } catch {
            return []
        }
    }

    private func runCommand(executable: String, arguments: [String]) async throws -> (terminationStatus: Int32, standardOutput: String, standardError: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { process in
                let stdout = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: (process.terminationStatus, stdout, stderr))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parsePingLatencies(_ output: String) -> [Int] {
        output
            .split(separator: "\n")
            .compactMap { line -> Int? in
                guard let range = line.range(of: "time=") else { return nil }
                let suffix = line[range.upperBound...]
                let value = suffix.prefix { $0.isNumber || $0 == "." }
                guard let milliseconds = Double(value) else { return nil }
                return Int(milliseconds.rounded())
            }
    }

    private func summarizedNetcatFailure(_ standardError: String) -> String {
        let trimmed = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "TCP probe failed"
        }
        if trimmed.localizedCaseInsensitiveContains("timed out") {
            return "Timed out"
        }
        if trimmed.localizedCaseInsensitiveContains("refused") {
            return "Connection refused"
        }
        if trimmed.localizedCaseInsensitiveContains("nodename nor servname provided") {
            return "DNS resolution failed"
        }
        return trimmed
    }

    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return Int(((Double(sorted[middle - 1]) + Double(sorted[middle])) / 2.0).rounded())
        }
        return sorted[middle]
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection]
    @Published private(set) var subscriptionSources: [SubscriptionSource]
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var connectionPhase: ConnectionPhase = .unconfigured
    @Published private(set) var proxyPhase: ProxyPhase = .disabled
    @Published private(set) var lastError: String?
    @Published private(set) var proxyEndpoint: ProxyEndpoint
    @Published private(set) var refreshingSubscriptionIDs: Set<UUID> = []
    @Published private(set) var refreshingHealthConnectionIDs: Set<UUID> = []
    @Published private(set) var menuBarAnimationTime: TimeInterval = 0

    private let parser: ConnectionLinkParser
    private let store: ConfigurationStore
    private let runtimeManager: XrayRuntimeManager
    private let proxyService: SystemProxyService
    private let subscriptionClient: SubscriptionClient
    private let healthProbeService: ConnectionHealthProbeService
    private let operationQueue = DispatchQueue(label: "dev.x.teleport.connection-operations", qos: .userInitiated)
    private let persistenceQueue = DispatchQueue(label: "dev.x.teleport.persistence", qos: .utility)
    private let healthFreshnessTTL: TimeInterval = 30 * 60
    private let automaticHealthProbeLimit = 1
    private let healthProbeConcurrencyLimit = 1
    private var autoRefreshTimerCancellable: AnyCancellable?
    private var menuBarAnimationCancellable: AnyCancellable?
    private var pendingHealthProbeIDs: [UUID] = []
    private var pendingHealthProbeIDSet: Set<UUID> = []
    private var activeHealthProbeTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingHealthProbeResults: [UUID: ConnectionHealthProbeResult] = [:]
    private var applyHealthResultsWorkItem: DispatchWorkItem?
    private var persistWorkItem: DispatchWorkItem?

    convenience init() {
        self.init(
            parser: ConnectionLinkParser(),
            store: ConfigurationStore(),
            runtimeManager: XrayRuntimeManager(),
            proxyService: SystemProxyService(),
            subscriptionClient: SubscriptionClient(),
            healthProbeService: ConnectionHealthProbeService()
        )
    }

    init(
        parser: ConnectionLinkParser,
        store: ConfigurationStore,
        runtimeManager: XrayRuntimeManager,
        proxyService: SystemProxyService,
        subscriptionClient: SubscriptionClient,
        healthProbeService: ConnectionHealthProbeService
    ) {
        self.parser = parser
        self.store = store
        self.runtimeManager = runtimeManager
        self.proxyService = proxyService
        self.subscriptionClient = subscriptionClient
        self.healthProbeService = healthProbeService

        let snapshot = store.load()
        proxyEndpoint = snapshot.proxyEndpoint
        subscriptionSources = snapshot.subscriptionSources

        savedConnections = snapshot.savedConnections.map { savedConnection in
            if let reparsedConfiguration = try? parser.parse(savedConnection.configuration.rawLink) {
                return SavedConnection(
                    id: savedConnection.id,
                    configuration: reparsedConfiguration,
                    savedAt: savedConnection.savedAt,
                    source: savedConnection.source,
                    healthCheck: savedConnection.healthCheck?.normalizedForPersistence
                )
            }
            return savedConnection
        }

        selectedConnectionID = snapshot.selectedConnectionID
        normalizeSelection()
        connectionPhase = savedConnections.isEmpty ? .unconfigured : .stopped
        startAutoRefreshTimer()
        updateMenuBarAnimation()
        scheduleInitialHealthRefresh()
    }

    var selectedConnection: SavedConnection? {
        guard let selectedConnectionID else { return savedConnections.first }
        return savedConnections.first { $0.id == selectedConnectionID } ?? savedConnections.first
    }

    var selectedConfiguration: ConnectionConfiguration? {
        selectedConnection?.configuration
    }

    var manualConnections: [SavedConnection] {
        savedConnections.filter { $0.source == nil }
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
            return savedConnections.isEmpty ? "Add a connection or subscription in Settings to get started" : "Select a connection to get started"
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

    func importedConnections(for sourceID: UUID) -> [SavedConnection] {
        savedConnections
            .filter { $0.source?.subscriptionSourceID == sourceID }
            .sorted { lhs, rhs in
                lhs.configuration.displayName.localizedCaseInsensitiveCompare(rhs.configuration.displayName) == .orderedAscending
            }
    }

    func importedConnectionCount(for sourceID: UUID) -> Int {
        importedConnections(for: sourceID).count
    }

    func subscriptionSource(for connection: SavedConnection) -> SubscriptionSource? {
        guard let sourceID = connection.source?.subscriptionSourceID else { return nil }
        return subscriptionSources.first { $0.id == sourceID }
    }

    func isRefreshingSubscription(_ sourceID: UUID) -> Bool {
        refreshingSubscriptionIDs.contains(sourceID)
    }

    func isRefreshingHealth(for connectionID: UUID) -> Bool {
        refreshingHealthConnectionIDs.contains(connectionID)
    }

    func healthCheck(for connection: SavedConnection) -> ConnectionHealthCheck {
        if refreshingHealthConnectionIDs.contains(connection.id) {
            var checking = connection.healthCheck ?? .unknown
            checking.state = .checking
            return checking
        }

        guard let healthCheck = connection.healthCheck else {
            return .unknown
        }

        let freshness = healthCheck.freshness(now: Date(), ttl: healthFreshnessTTL)
        switch freshness {
        case .fresh:
            return healthCheck
        case .stale:
            var stale = healthCheck
            stale.state = .unknown
            return stale
        case .unknown:
            return .unknown
        }
    }

    func healthSummary(for connection: SavedConnection) -> String {
        let healthCheck = healthCheck(for: connection)
        switch healthCheck.state {
        case .reachable:
            if let latency = healthCheck.latencyMilliseconds {
                return "Latency \(latency) ms"
            }
            return "Available"
        case .unreachable:
            return healthCheck.failureSummary ?? "Unavailable"
        case .checking:
            return "Checking…"
        case .unknown:
            if let checkedAt = connection.healthCheck?.checkedAt {
                return "Unknown • checked \(Self.relativeFormatter.localizedString(for: checkedAt, relativeTo: Date()))"
            }
            return "Not checked"
        }
    }

    func refreshConnectionHealth(id: UUID, force: Bool = true) {
        enqueueHealthProbes(for: [id], force: force, priority: true)
    }

    func refreshSubscriptionHealth(id: UUID, force: Bool = true) {
        let ids = importedConnections(for: id).map(\.id)
        enqueueHealthProbes(for: ids, force: force, priority: true)
    }

    func refreshVisibleConnectionHealth(force: Bool = true) {
        enqueueHealthProbes(for: savedConnections.map(\.id), force: force, priority: true)
    }

    @discardableResult
    func addConnection(from rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Paste a connection or subscription URL first"
            return false
        }

        if looksLikeSubscriptionURL(trimmed) {
            return addSubscription(from: trimmed)
        } else {
            return addManualConnection(from: trimmed)
        }
    }

    func removeConnection(id: UUID) {
        guard let index = savedConnections.firstIndex(where: { $0.id == id }) else { return }

        if !canChangeSelection && selectedConnectionID == id {
            lastError = "Disconnect before removing the active connection"
            return
        }

        let removedConnection = savedConnections.remove(at: index)
        cancelHealthProbe(id: id)
        if selectedConnectionID == removedConnection.id {
            recoverSelection(afterRemovingConnectionAt: index)
        } else {
            normalizeSelection()
        }

        lastError = nil
        persistSettingError()
    }

    func removeSubscription(id: UUID) {
        let affectedConnections = importedConnections(for: id)

        if !canChangeSelection,
           affectedConnections.contains(where: { $0.id == selectedConnectionID }) {
            lastError = "Disconnect before removing the active subscription"
            return
        }

        savedConnections.removeAll { $0.source?.subscriptionSourceID == id }
        subscriptionSources.removeAll { $0.id == id }
        refreshingSubscriptionIDs.remove(id)
        let removedIDs = Set(affectedConnections.map(\.id))
        cancelHealthProbes(ids: removedIDs)
        normalizeSelection()
        lastError = nil
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
        enqueueHealthProbes(for: [id], force: false, priority: true)
    }

    func refreshSubscription(id: UUID) {
        refreshSubscription(id: id, autoSelectFirstImported: false)
    }

    func updateSubscriptionSettings(id: UUID, customName: String, urlString: String, autoUpdateIntervalMinutes: Int?) {
        guard let existingSource = subscriptionSources.first(where: { $0.id == id }) else { return }

        do {
            let validatedURL = try validateSubscriptionURL(urlString)
            let normalizedURL = validatedURL.absoluteString

            if subscriptionSources.contains(where: { $0.id != id && $0.urlString.caseInsensitiveCompare(normalizedURL) == .orderedSame }) {
                throw SubscriptionError.duplicateSource
            }

            let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            let urlChanged = existingSource.urlString.caseInsensitiveCompare(normalizedURL) != .orderedSame

            updateSubscriptionSource(id) { source in
                source.title = trimmedName
                source.urlString = normalizedURL
                source.autoUpdateIntervalMinutes = autoUpdateIntervalMinutes
                if urlChanged {
                    source.lastError = nil
                    source.lastRefreshedAt = nil
                    source.lastSkippedCount = 0
                }
            }

            if urlChanged {
                savedConnections.removeAll { $0.source?.subscriptionSourceID == id }
                if selectedConnection?.source?.subscriptionSourceID == id {
                    normalizeSelection()
                }
            }

            lastError = nil
            persistSettingError()

            if urlChanged {
                refreshSubscription(id: id, autoSelectFirstImported: false)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() {
        lastError = nil
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
                    self?.updateMenuBarAnimation()
                }
            } catch {
                runtimeManager.stop()

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .failed
                    self?.proxyPhase = .failed
                    self?.lastError = error.localizedDescription
                    self?.updateMenuBarAnimation()
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
                        self?.updateMenuBarAnimation()
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        self?.proxyPhase = .failed
                        self?.lastError = error.localizedDescription
                        self?.updateMenuBarAnimation()
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
                self?.updateMenuBarAnimation()
            }
        }
    }

    func handleAppTermination() {
        teardownConnection(resetError: true)
    }

    private func addManualConnection(from rawLink: String) -> Bool {
        do {
            let configuration = try parser.parse(rawLink)
            let savedConnection = SavedConnection(id: UUID(), configuration: configuration, savedAt: Date(), source: nil)
            savedConnections.append(savedConnection)
            selectedConnectionID = savedConnection.id
            connectionPhase = .stopped
            lastError = nil
            updateMenuBarAnimation()
            try persist()
            enqueueHealthProbes(for: [savedConnection.id], force: true, priority: true)
            return true
        } catch {
            lastError = error.localizedDescription
            if savedConnections.isEmpty {
                connectionPhase = .unconfigured
            }
            return false
        }
    }

    private func addSubscription(from rawURL: String) -> Bool {
        do {
            let url = try validateSubscriptionURL(rawURL)
            let normalizedURL = url.absoluteString

            if subscriptionSources.contains(where: { $0.urlString.caseInsensitiveCompare(normalizedURL) == .orderedSame }) {
                throw SubscriptionError.duplicateSource
            }

            let source = SubscriptionSource(
                id: UUID(),
                urlString: normalizedURL,
                title: subscriptionTitle(for: url),
                savedAt: Date(),
                autoUpdateIntervalMinutes: nil
            )

            subscriptionSources.append(source)
            lastError = nil
            persistSettingError()
            refreshSubscription(id: source.id, autoSelectFirstImported: savedConnections.isEmpty)
            return true
        } catch {
            lastError = error.localizedDescription
            if savedConnections.isEmpty {
                connectionPhase = .unconfigured
            }
            return false
        }
    }

    private func refreshSubscription(id: UUID, autoSelectFirstImported: Bool) {
        guard let source = subscriptionSources.first(where: { $0.id == id }) else { return }
        guard let selectedConnection else {
            startSubscriptionRefresh(for: source, autoSelectFirstImported: autoSelectFirstImported)
            return
        }

        if !canChangeSelection,
           selectedConnection.source?.subscriptionSourceID == id {
            lastError = "Disconnect before refreshing the active subscription"
            return
        }

        startSubscriptionRefresh(for: source, autoSelectFirstImported: autoSelectFirstImported)
    }

    private func startSubscriptionRefresh(for source: SubscriptionSource, autoSelectFirstImported: Bool) {
        refreshingSubscriptionIDs.insert(source.id)
        updateSubscriptionSource(source.id) {
            $0.lastError = nil
        }
        lastError = nil
        persistSettingError()

        let parser = parser
        let subscriptionClient = subscriptionClient

        operationQueue.async { [weak self] in
            do {
                guard let url = URL(string: source.urlString) else {
                    throw SubscriptionError.invalidURL
                }

                let links = try subscriptionClient.fetchCandidateLinks(from: url)
                let importResult = try Self.importSubscriptionEntries(links: links, parser: parser, sourceID: source.id)

                Task { @MainActor [weak self] in
                    self?.applyImportedEntries(
                        importResult.importedEntries,
                        skippedCount: importResult.skippedCount,
                        to: source.id,
                        fetchedAt: Date(),
                        autoSelectFirstImported: autoSelectFirstImported
                    )
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.refreshingSubscriptionIDs.remove(source.id)
                    self?.updateSubscriptionSource(source.id) {
                        $0.lastError = error.localizedDescription
                    }
                    self?.lastError = error.localizedDescription
                    self?.persistSettingError()
                }
            }
        }
    }

    nonisolated private static func importSubscriptionEntries(
        links: [String],
        parser: ConnectionLinkParser,
        sourceID: UUID
    ) throws -> SubscriptionImportResult {
        var importedEntries: [ImportedSubscriptionEntry] = []
        var skippedCount = 0

        for rawLink in links {
            do {
                let configuration = try parser.parse(rawLink)
                importedEntries.append(
                    ImportedSubscriptionEntry(
                        sourceEntryID: rawLink.trimmingCharacters(in: .whitespacesAndNewlines),
                        configuration: configuration
                    )
                )
            } catch {
                skippedCount += 1
            }
        }

        _ = sourceID

        guard !importedEntries.isEmpty else {
            throw SubscriptionError.noSupportedEntries
        }

        return SubscriptionImportResult(importedEntries: importedEntries, skippedCount: skippedCount)
    }

    private func applyImportedEntries(
        _ importedEntries: [ImportedSubscriptionEntry],
        skippedCount: Int,
        to sourceID: UUID,
        fetchedAt: Date,
        autoSelectFirstImported: Bool
    ) {
        let replacementResult = SubscriptionConnectionReconciler().reconcile(
            existingConnections: savedConnections,
            sourceID: sourceID,
            selectedConnectionID: selectedConnectionID,
            importedEntries: importedEntries,
            fetchedAt: fetchedAt,
            autoSelectFirstImported: autoSelectFirstImported
        )

        savedConnections = replacementResult.savedConnections
        selectedConnectionID = replacementResult.selectedConnectionID

        updateSubscriptionSource(sourceID) {
            $0.lastRefreshedAt = fetchedAt
            $0.lastSkippedCount = skippedCount
            $0.lastError = skippedCount > 0 ? "Skipped \(skippedCount) unsupported entries during last refresh" : nil
        }

        refreshingSubscriptionIDs.remove(sourceID)
        lastError = nil
        connectionPhase = savedConnections.isEmpty ? .unconfigured : .stopped
        updateMenuBarAnimation()
        persistSettingError()
        refreshSubscriptionHealth(id: sourceID, force: true)
    }

    private func validateSubscriptionURL(_ rawURL: String) throws -> URL {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw SubscriptionError.invalidURL
        }
        return url
    }

    private func subscriptionTitle(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host
        }
        return url.absoluteString
    }

    private func looksLikeSubscriptionURL(_ value: String) -> Bool {
        guard let scheme = URLComponents(string: value)?.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private func startAutoRefreshTimer() {
        autoRefreshTimerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performScheduledSubscriptionRefreshes()
                self?.performScheduledHealthRefreshes()
            }
    }

    private func performScheduledSubscriptionRefreshes() {
        let now = Date()

        for source in subscriptionSources {
            guard let intervalMinutes = source.autoUpdateIntervalMinutes,
                  intervalMinutes > 0,
                  !refreshingSubscriptionIDs.contains(source.id) else {
                continue
            }

            let referenceDate = source.lastRefreshedAt ?? source.savedAt
            guard now.timeIntervalSince(referenceDate) >= TimeInterval(intervalMinutes * 60) else {
                continue
            }

            refreshSubscription(id: source.id, autoSelectFirstImported: false)
        }
    }

    private func scheduleInitialHealthRefresh() {
        guard let selectedConnectionID else { return }
        enqueueHealthProbes(for: [selectedConnectionID], force: false, priority: true)
    }

    private func performScheduledHealthRefreshes() {
        guard let selectedConnection,
              needsHealthRefresh(for: selectedConnection) else {
            return
        }

        enqueueHealthProbes(for: [selectedConnection.id], force: false, priority: false)
    }

    private func needsHealthRefresh(for connection: SavedConnection) -> Bool {
        guard let healthCheck = connection.healthCheck else {
            return true
        }

        switch healthCheck.freshness(now: Date(), ttl: healthFreshnessTTL) {
        case .fresh:
            return false
        case .stale, .unknown:
            return true
        }
    }

    private func enqueueHealthProbes(for ids: [UUID], force: Bool, priority: Bool) {
        guard !ids.isEmpty else { return }

        for id in ids {
            guard let connection = savedConnections.first(where: { $0.id == id }) else { continue }
            guard force || needsHealthRefresh(for: connection) else { continue }
            guard activeHealthProbeTasks[id] == nil else { continue }
            guard !pendingHealthProbeIDSet.contains(id) else { continue }

            if priority {
                pendingHealthProbeIDs.insert(id, at: 0)
            } else {
                pendingHealthProbeIDs.append(id)
            }
            pendingHealthProbeIDSet.insert(id)
        }

        drainHealthProbeQueue()
    }

    private func drainHealthProbeQueue() {
        while activeHealthProbeTasks.count < healthProbeConcurrencyLimit,
              let nextID = pendingHealthProbeIDs.first {
            pendingHealthProbeIDs.removeFirst()
            pendingHealthProbeIDSet.remove(nextID)

            guard let connection = savedConnections.first(where: { $0.id == nextID }) else {
                continue
            }

            refreshingHealthConnectionIDs.insert(nextID)
            let task = Task.detached(priority: .utility) { [healthProbeService, connection, nextID] in
                let result = await healthProbeService.probe(connection)
                await MainActor.run {
                    self.enqueueHealthProbeResult(result, for: nextID)
                }
            }
            activeHealthProbeTasks[nextID] = task
        }
    }

    private func enqueueHealthProbeResult(_ result: ConnectionHealthProbeResult, for connectionID: UUID) {
        activeHealthProbeTasks[connectionID] = nil
        pendingHealthProbeResults[connectionID] = result
        scheduleHealthResultApplication()
        drainHealthProbeQueue()
    }

    private func scheduleHealthResultApplication() {
        guard applyHealthResultsWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyPendingHealthProbeResults()
            }
        }

        applyHealthResultsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func applyPendingHealthProbeResults() {
        applyHealthResultsWorkItem = nil
        guard !pendingHealthProbeResults.isEmpty else { return }

        let pendingResults = pendingHealthProbeResults
        pendingHealthProbeResults = [:]

        for (connectionID, result) in pendingResults {
            refreshingHealthConnectionIDs.remove(connectionID)

            guard let index = savedConnections.firstIndex(where: { $0.id == connectionID }) else {
                continue
            }

            savedConnections[index].healthCheck = ConnectionHealthCheck(
                state: result.state,
                checkedAt: result.checkedAt,
                latencyMilliseconds: result.latencyMilliseconds,
                failureSummary: result.failureSummary
            )
        }

        schedulePersist()
    }

    private func cancelHealthProbe(id: UUID) {
        activeHealthProbeTasks[id]?.cancel()
        activeHealthProbeTasks[id] = nil
        refreshingHealthConnectionIDs.remove(id)
        pendingHealthProbeIDSet.remove(id)
        pendingHealthProbeIDs.removeAll { $0 == id }
    }

    private func cancelHealthProbes(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            cancelHealthProbe(id: id)
        }
    }

    private func updateSubscriptionSource(_ id: UUID, mutate: (inout SubscriptionSource) -> Void) {
        guard let index = subscriptionSources.firstIndex(where: { $0.id == id }) else { return }
        mutate(&subscriptionSources[index])
    }

    private func recoverSelection(afterRemovingConnectionAt index: Int) {
        if savedConnections.indices.contains(index) {
            selectedConnectionID = savedConnections[index].id
        } else {
            selectedConnectionID = savedConnections.last?.id
        }
        normalizeSelection()
    }

    private func normalizeSelection() {
        if let selectedConnectionID,
           savedConnections.contains(where: { $0.id == selectedConnectionID }) {
            return
        }

        selectedConnectionID = savedConnections.first?.id
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
                    self?.updateMenuBarAnimation()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.proxyPhase = .failed
                    if !resetError {
                        self?.lastError = error.localizedDescription
                    }
                    self?.updateMenuBarAnimation()
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
            self.updateMenuBarAnimation()
        }
    }

    private func updateMenuBarAnimation() {
        let shouldAnimate = isConnected

        guard shouldAnimate else {
            menuBarAnimationCancellable?.cancel()
            menuBarAnimationCancellable = nil
            menuBarAnimationTime = 0
            return
        }

        guard menuBarAnimationCancellable == nil else { return }

        menuBarAnimationTime = Date().timeIntervalSinceReferenceDate
        menuBarAnimationCancellable = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                self?.menuBarAnimationTime = now.timeIntervalSinceReferenceDate
            }
    }

    private func persistSettingError() {
        do {
            try persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func schedulePersist() {
        let snapshot = makeSnapshot()
        persistWorkItem?.cancel()

        let workItem = DispatchWorkItem { [store] in
            do {
                try store.save(snapshot)
            } catch {
                Task { @MainActor [weak self] in
                    self?.lastError = error.localizedDescription
                }
            }
        }

        persistWorkItem = workItem
        persistenceQueue.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private func makeSnapshot() -> AppSnapshot {
        let persistedConnections = savedConnections.map { connection in
            var normalizedConnection = connection
            normalizedConnection.healthCheck = connection.healthCheck?.normalizedForPersistence
            return normalizedConnection
        }

        return AppSnapshot(
            savedConnections: persistedConnections,
            subscriptionSources: subscriptionSources,
            selectedConnectionID: selectedConnectionID ?? savedConnections.first?.id,
            proxyEndpoint: proxyEndpoint
        )
    }

    private func persist() throws {
        try store.save(makeSnapshot())
    }
}

extension AppViewModel {
    fileprivate static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
