import AppKit
import CFNetwork
import Combine
import Darwin
import Foundation
import Network
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

        return try writeConfig(
            for: configuration,
            to: directory.appendingPathComponent("xray-config.json")
        )
    }

    func writeConfig(for configuration: ConnectionConfiguration, to outputURL: URL) throws -> URL {
        let directory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload = makePayload(configuration: configuration)
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputURL, options: .atomic)
        return outputURL
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
    private let errorBufferLock = NSLock()
    private var errorBuffer = Data()

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
        errorBufferLock.lock()
        errorBuffer = Data()
        errorBufferLock.unlock()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.errorBufferLock.lock()
            self.errorBuffer.append(data)
            self.errorBufferLock.unlock()
        }

        process.standardError = pipe
        process.standardOutput = Pipe()
        errorPipe = pipe

        try process.run()
        self.process = process
    }

    func waitUntilLocalProxyReady(endpoint: ProxyEndpoint, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            guard process?.isRunning == true else { return false }

            if Self.canOpenTCPConnection(host: endpoint.host, port: endpoint.httpPort, timeout: 0.2),
               Self.canOpenTCPConnection(host: endpoint.host, port: endpoint.socksPort, timeout: 0.2) {
                return true
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        return false
    }

    func stop() {
        guard let process else {
            cleanupPipe()
            return
        }

        if process.isRunning {
            process.terminate()

            let deadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }

            process.waitUntilExit()
        }

        self.process = nil
        cleanupPipe()
    }

    func stopAndCaptureErrorOutput() -> String? {
        stop()
        return capturedErrorOutput()
    }

    func capturedErrorOutput() -> String? {
        errorBufferLock.lock()
        defer { errorBufferLock.unlock() }
        guard !errorBuffer.isEmpty else { return nil }
        return String(data: errorBuffer, encoding: .utf8)
    }

    private func cleanupPipe() {
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe = nil
    }

    private func assetDirectoryURL() -> URL? {
        bundle.url(forResource: "xray-assets", withExtension: nil)
    }

    private static func canOpenTCPConnection(host: String, port: Int, timeout: TimeInterval) -> Bool {
        guard let rawPort = UInt16(exactly: port),
              let endpointPort = NWEndpoint.Port(rawValue: rawPort) else {
            return false
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var didComplete = false
        var isReady = false

        func finish(_ ready: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            isReady = ready
            semaphore.signal()
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(true)
            case .failed, .cancelled:
                finish(false)
            default:
                break
            }
        }

        let queue = DispatchQueue(label: "dev.x.teleport.xray-readiness", qos: .userInitiated)
        connection.start(queue: queue)
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            finish(false)
        }
        connection.cancel()
        return isReady
    }

    enum RuntimeError: LocalizedError {
        case binaryNotFound
        case startupTimedOut(String?)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "Bundled Xray binary was not found in the app resources."
            case .startupTimedOut(let detail):
                if let detail, !detail.isEmpty {
                    return "Xray did not become ready: \(detail)"
                }
                return "Xray did not become ready before enabling the system proxy."
            }
        }
    }
}

final class SystemProxyService: @unchecked Sendable {
    private let processRunner: (Process) throws -> Void
    private let fileManager: FileManager
    private let commandTimeout: TimeInterval
    private var lastEnabledEndpoint: ProxyEndpoint?

    init(
        processRunner: @escaping (Process) throws -> Void = { try $0.run() },
        fileManager: FileManager = .default,
        commandTimeout: TimeInterval = 5
    ) {
        self.processRunner = processRunner
        self.fileManager = fileManager
        self.commandTimeout = commandTimeout
    }

    func hasSavedProxySnapshot() -> Bool {
        fileManager.fileExists(atPath: proxySnapshotURL.path)
    }

    func enableProxy(endpoint: ProxyEndpoint) throws {
        try persistCurrentProxyStateIfNeeded(endpoint: endpoint)

        do {
            try setWebProxy(enabled: true, host: endpoint.host, port: endpoint.httpPort)
            try setSecureWebProxy(enabled: true, host: endpoint.host, port: endpoint.httpPort)
            try setSOCKSProxy(enabled: true, host: endpoint.host, port: endpoint.socksPort)
            lastEnabledEndpoint = endpoint
        } catch {
            try? restoreSavedProxyState()
            throw error
        }
    }

    func disableProxy() throws {
        if hasSavedProxySnapshot() {
            try restoreSavedProxyState()
            return
        }

        if let lastEnabledEndpoint {
            try disableProxyIfMatching(endpoint: lastEnabledEndpoint)
            self.lastEnabledEndpoint = nil
            return
        }

        // Safety fallback for stale settings created before crash-safe snapshots existed.
        // It only turns off proxies that still point at Teleport's default local endpoint.
        try disableProxyIfMatching(endpoint: .default)
    }

    func restoreSavedProxyState() throws {
        guard let snapshot = try loadSavedProxySnapshot() else { return }

        let activeServices = Set(try activeNetworkServices())
        for serviceSnapshot in snapshot.services where activeServices.contains(serviceSnapshot.serviceName) {
            try restoreWebProxy(serviceSnapshot.webProxy, service: serviceSnapshot.serviceName)
            try restoreSecureWebProxy(serviceSnapshot.secureWebProxy, service: serviceSnapshot.serviceName)
            try restoreSOCKSProxy(serviceSnapshot.socksProxy, service: serviceSnapshot.serviceName)
        }

        try? fileManager.removeItem(at: proxySnapshotURL)
        lastEnabledEndpoint = nil
    }

    private func persistCurrentProxyStateIfNeeded(endpoint: ProxyEndpoint) throws {
        guard !hasSavedProxySnapshot() else { return }

        let services = try activeNetworkServices()
        let snapshots = try services.map { service in
            NetworkServiceProxySnapshot(
                serviceName: service,
                webProxy: try readWebProxy(service: service),
                secureWebProxy: try readSecureWebProxy(service: service),
                socksProxy: try readSOCKSProxy(service: service)
            )
        }

        if snapshots.contains(where: { $0.hasEnabledAuthenticatedProxy }) {
            throw ProxyError.authenticatedProxyCannotBePreserved
        }

        let snapshot = ProxyStateSnapshot(createdAt: Date(), endpoint: endpoint, services: snapshots)
        try fileManager.createDirectory(at: proxyStateDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: proxySnapshotURL, options: [.atomic])
    }

    private func loadSavedProxySnapshot() throws -> ProxyStateSnapshot? {
        guard fileManager.fileExists(atPath: proxySnapshotURL.path) else { return nil }
        let data = try Data(contentsOf: proxySnapshotURL)
        return try JSONDecoder().decode(ProxyStateSnapshot.self, from: data)
    }

    private var proxyStateDirectoryURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("teleport", isDirectory: true)
    }

    private var proxySnapshotURL: URL {
        proxyStateDirectoryURL.appendingPathComponent("system-proxy-snapshot.json")
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

    private func readWebProxy(service: String) throws -> NetworkProxySettings {
        try readProxySettings(arguments: ["-getwebproxy", service])
    }

    private func readSecureWebProxy(service: String) throws -> NetworkProxySettings {
        try readProxySettings(arguments: ["-getsecurewebproxy", service])
    }

    private func readSOCKSProxy(service: String) throws -> NetworkProxySettings {
        try readProxySettings(arguments: ["-getsocksfirewallproxy", service])
    }

    private func readProxySettings(arguments: [String]) throws -> NetworkProxySettings {
        let result = try runNetworkSetup(arguments: arguments)
        return NetworkProxySettings(networkSetupOutput: result.standardOutput)
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

    private func restoreWebProxy(_ settings: NetworkProxySettings, service: String) throws {
        try restoreProxySettings(settings, service: service, setCommand: "-setwebproxy", stateCommand: "-setwebproxystate")
    }

    private func restoreSecureWebProxy(_ settings: NetworkProxySettings, service: String) throws {
        try restoreProxySettings(settings, service: service, setCommand: "-setsecurewebproxy", stateCommand: "-setsecurewebproxystate")
    }

    private func restoreSOCKSProxy(_ settings: NetworkProxySettings, service: String) throws {
        try restoreProxySettings(settings, service: service, setCommand: "-setsocksfirewallproxy", stateCommand: "-setsocksfirewallproxystate")
    }

    private func restoreProxySettings(_ settings: NetworkProxySettings, service: String, setCommand: String, stateCommand: String) throws {
        let setArguments = [setCommand, service, settings.server ?? "", String(settings.port ?? 0)]
        let stateArguments = [stateCommand, service, settings.enabled ? "on" : "off"]

        if settings.enabled {
            try runNetworkSetup(arguments: setArguments)
            try runNetworkSetup(arguments: stateArguments)
        } else {
            try runNetworkSetup(arguments: stateArguments)
            try runNetworkSetup(arguments: setArguments)
            try runNetworkSetup(arguments: stateArguments)
        }
    }

    private func disableProxyIfMatching(endpoint: ProxyEndpoint) throws {
        for service in try activeNetworkServices() {
            let webProxy = try readWebProxy(service: service)
            if webProxy.matches(host: endpoint.host, port: endpoint.httpPort) {
                try clearProxy(service: service, setCommand: "-setwebproxy", stateCommand: "-setwebproxystate")
            }

            let secureWebProxy = try readSecureWebProxy(service: service)
            if secureWebProxy.matches(host: endpoint.host, port: endpoint.httpPort) {
                try clearProxy(service: service, setCommand: "-setsecurewebproxy", stateCommand: "-setsecurewebproxystate")
            }

            let socksProxy = try readSOCKSProxy(service: service)
            if socksProxy.matches(host: endpoint.host, port: endpoint.socksPort) {
                try clearProxy(service: service, setCommand: "-setsocksfirewallproxy", stateCommand: "-setsocksfirewallproxystate")
            }
        }
    }

    private func clearProxy(service: String, setCommand: String, stateCommand: String) throws {
        try runNetworkSetup(arguments: [stateCommand, service, "off"])
        try runNetworkSetup(arguments: [setCommand, service, "", "0"])
        try runNetworkSetup(arguments: [stateCommand, service, "off"])
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

        let deadline = Date().addingTimeInterval(commandTimeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
            throw ProxyError.commandTimedOut(arguments: arguments)
        }

        let stdout = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        guard process.terminationStatus == 0 else {
            throw ProxyError.commandFailed(arguments: arguments, standardError: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return CommandResult(standardOutput: stdout, standardError: stderr)
    }

    private struct ProxyStateSnapshot: Codable {
        let createdAt: Date
        let endpoint: ProxyEndpoint
        let services: [NetworkServiceProxySnapshot]
    }

    private struct NetworkServiceProxySnapshot: Codable {
        let serviceName: String
        let webProxy: NetworkProxySettings
        let secureWebProxy: NetworkProxySettings
        let socksProxy: NetworkProxySettings

        var hasEnabledAuthenticatedProxy: Bool {
            [webProxy, secureWebProxy, socksProxy].contains { $0.enabled && $0.authenticated }
        }
    }

    private struct NetworkProxySettings: Codable, Equatable {
        let enabled: Bool
        let server: String?
        let port: Int?
        let authenticated: Bool

        init(enabled: Bool, server: String?, port: Int?, authenticated: Bool = false) {
            self.enabled = enabled
            self.server = server
            self.port = port
            self.authenticated = authenticated
        }

        init(networkSetupOutput: String) {
            var enabled = false
            var server: String?
            var port: Int?
            var authenticated = false

            for line in networkSetupOutput.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }

                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

                switch key {
                case "enabled":
                    enabled = Self.parseBoolean(value)
                case "server":
                    server = value.isEmpty ? nil : value
                case "port":
                    port = Int(value)
                case "authenticated proxy enabled":
                    authenticated = Self.parseBoolean(value)
                default:
                    continue
                }
            }

            self.enabled = enabled
            self.server = server
            self.port = port
            self.authenticated = authenticated
        }

        func matches(host: String, port expectedPort: Int) -> Bool {
            enabled
                && server?.caseInsensitiveCompare(host) == .orderedSame
                && port == expectedPort
        }

        private static func parseBoolean(_ value: String) -> Bool {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "yes", "true", "1", "on":
                return true
            default:
                return false
            }
        }
    }

    struct CommandResult {
        let standardOutput: String
        let standardError: String
    }

    enum ProxyError: LocalizedError {
        case authenticatedProxyCannotBePreserved
        case commandFailed(arguments: [String], standardError: String)
        case commandTimedOut(arguments: [String])

        var errorDescription: String? {
            switch self {
            case .authenticatedProxyCannotBePreserved:
                return "Existing authenticated system proxy settings cannot be safely preserved because macOS does not expose the saved proxy password. Disable those proxies before connecting."
            case let .commandFailed(arguments, standardError):
                let command = arguments.joined(separator: " ")
                if standardError.isEmpty {
                    return "Failed to update system proxy with command: \(command)"
                }
                return "Failed to update system proxy with command: \(command)\n\(standardError)"
            case let .commandTimedOut(arguments):
                let command = arguments.joined(separator: " ")
                return "Timed out while updating system proxy with command: \(command)"
            }
        }
    }
}
struct ConnectionHealthProbeResult {
    let state: ConnectionHealthState
    let checkedAt: Date
    let latencyMilliseconds: Int?
    let latencyKind: ConnectionHealthLatencyKind?
    let failureSummary: String?
}

final class ConnectionHealthProbeService: @unchecked Sendable {
    private let attemptCount: Int
    private let tcpTimeoutSeconds: Int
    private let tunnelProbeTimeoutSeconds: Int
    private let tunnelProbeURL: URL
    private let bundle: Bundle
    private let fileManager: FileManager

    init(
        attemptCount: Int = 4,
        tcpTimeoutSeconds: Int = 3,
        tunnelProbeTimeoutSeconds: Int = 8,
        tunnelProbeURL: URL = URL(string: "https://cp.cloudflare.com/generate_204")!,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.attemptCount = max(1, attemptCount)
        self.tcpTimeoutSeconds = max(1, tcpTimeoutSeconds)
        self.tunnelProbeTimeoutSeconds = max(2, tunnelProbeTimeoutSeconds)
        self.tunnelProbeURL = tunnelProbeURL
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func probe(_ connection: SavedConnection) async -> ConnectionHealthProbeResult {
        guard UInt16(exactly: connection.configuration.port) != nil else {
            return ConnectionHealthProbeResult(
                state: .unreachable,
                checkedAt: Date(),
                latencyMilliseconds: nil,
                latencyKind: nil,
                failureSummary: "Invalid port"
            )
        }

        let checkedAt = Date()
        let tunnelResult = await proxyLatencyCheck(connection)

        if let tunnelLatency = tunnelResult.latencyMilliseconds {
            return ConnectionHealthProbeResult(
                state: .reachable,
                checkedAt: checkedAt,
                latencyMilliseconds: tunnelLatency,
                latencyKind: .proxyRequest,
                failureSummary: nil
            )
        }

        return ConnectionHealthProbeResult(
            state: .unreachable,
            checkedAt: checkedAt,
            latencyMilliseconds: nil,
            latencyKind: nil,
            failureSummary: tunnelResult.failureSummary ?? "Unavailable"
        )
    }

    private func tcpAvailabilityCheck(_ connection: SavedConnection) async -> (isReachable: Bool, latencyMilliseconds: Int?, failureSummary: String?) {
        guard let rawPort = UInt16(exactly: connection.configuration.port),
              let port = NWEndpoint.Port(rawValue: rawPort) else {
            return (false, nil, "Invalid port")
        }

        let host = NWEndpoint.Host(connection.configuration.host)
        var successfulLatencies: [Int] = []
        var lastFailureSummary: String?

        for _ in 0..<attemptCount {
            let sample = await tcpLatencySample(host: host, port: port, connectionID: connection.id)
            if sample.isReachable, let latency = sample.latencyMilliseconds {
                successfulLatencies.append(latency)
            } else {
                lastFailureSummary = sample.failureSummary
            }
        }

        guard !successfulLatencies.isEmpty else {
            return (false, nil, lastFailureSummary ?? "Unavailable")
        }

        return (true, Self.bestObservedLatency(successfulLatencies), nil)
    }

    private func proxyLatencyCheck(_ connection: SavedConnection) async -> (latencyMilliseconds: Int?, failureSummary: String?) {
        let probeEndpoint = temporaryProbeEndpoint()
        let runtimeManager = XrayRuntimeManager(bundle: bundle)
        let writer = XrayConfigurationWriter(proxyEndpoint: probeEndpoint)
        let probeDirectory = fileManager.temporaryDirectory.appendingPathComponent("teleport-health-\(connection.id.uuidString)-\(UUID().uuidString)", isDirectory: true)
        let configURL = probeDirectory.appendingPathComponent("xray-config.json")

        defer {
            try? fileManager.removeItem(at: probeDirectory)
        }

        do {
            _ = try writer.writeConfig(for: connection.configuration, to: configURL)
            try runtimeManager.start(configURL: configURL)
            let isReady = await waitForLocalProxyReady(endpoint: probeEndpoint, connectionID: connection.id)
            guard isReady else {
                let runtimeError = runtimeManager.stopAndCaptureErrorOutput()?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (nil, runtimeError.map(Self.summarizedRuntimeFailure) ?? "Proxy startup timed out")
            }

            let requestResult = try await proxyRequestLatencySample(endpoint: probeEndpoint)
            runtimeManager.stop()
            return (requestResult, nil)
        } catch {
            let runtimeError = runtimeManager.stopAndCaptureErrorOutput()?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let runtimeError, !runtimeError.isEmpty {
                return (nil, Self.summarizedRuntimeFailure(runtimeError))
            }
            return (nil, Self.summarizedProbeFailure(error))
        }
    }

    private func proxyRequestLatencySample(endpoint: ProxyEndpoint) async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(tunnelProbeTimeoutSeconds)
        configuration.timeoutIntervalForResource = TimeInterval(tunnelProbeTimeoutSeconds)
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 1,
            kCFNetworkProxiesHTTPProxy as String: endpoint.host,
            kCFNetworkProxiesHTTPPort as String: endpoint.httpPort,
            kCFNetworkProxiesHTTPSEnable as String: 1,
            kCFNetworkProxiesHTTPSProxy as String: endpoint.host,
            kCFNetworkProxiesHTTPSPort as String: endpoint.httpPort
        ]

        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
        }

        let probeCandidates = [
            tunnelProbeURL,
            URL(string: "https://www.gstatic.com/generate_204")!,
            URL(string: "https://www.google.com/generate_204")!
        ]

        var lastError: Error?

        for probeURL in probeCandidates {
            do {
                var request = URLRequest(url: probeURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: TimeInterval(tunnelProbeTimeoutSeconds))
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue("no-cache", forHTTPHeaderField: "Pragma")

                let startTime = DispatchTime.now().uptimeNanoseconds
                let (_, response) = try await session.data(for: request)
                let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startTime

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ProbeError.invalidResponse
                }

                guard (200 ... 399).contains(httpResponse.statusCode) else {
                    throw ProbeError.httpStatus(httpResponse.statusCode)
                }

                return max(1, Int((Double(elapsedNanoseconds) / 1_000_000).rounded()))
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ProbeError.invalidResponse
    }

    private func waitForLocalProxyReady(endpoint: ProxyEndpoint, connectionID: UUID) async -> Bool {
        guard let port = NWEndpoint.Port(rawValue: UInt16(endpoint.httpPort)) else {
            return false
        }

        let host = NWEndpoint.Host(endpoint.host)
        let attemptLimit = 20

        for _ in 0..<attemptLimit {
            let sample = await tcpLatencySample(host: host, port: port, connectionID: connectionID)
            if sample.isReachable {
                return true
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        return false
    }

    private func temporaryProbeEndpoint() -> ProxyEndpoint {
        let basePort = Int.random(in: 20000 ... 45000)
        return ProxyEndpoint(host: "127.0.0.1", httpPort: basePort, socksPort: basePort + 1)
    }

    private func tcpLatencySample(host: NWEndpoint.Host, port: NWEndpoint.Port, connectionID: UUID) async -> (isReachable: Bool, latencyMilliseconds: Int?, failureSummary: String?) {
        let startTime = DispatchTime.now().uptimeNanoseconds

        return await withCheckedContinuation { continuation in
            final class ResumeState: @unchecked Sendable {
                let lock = NSLock()
                var didResume = false
            }

            let resumeState = ResumeState()
            let queue = DispatchQueue(label: "dev.x.teleport.health-probe.\(connectionID.uuidString)", qos: .utility)
            let nwConnection = NWConnection(host: host, port: port, using: .tcp)

            @Sendable func finish(isReachable: Bool, latencyMilliseconds: Int?, failureSummary: String?) {
                resumeState.lock.lock()
                defer { resumeState.lock.unlock() }
                guard !resumeState.didResume else { return }
                resumeState.didResume = true
                nwConnection.cancel()
                continuation.resume(returning: (isReachable, latencyMilliseconds, failureSummary))
            }

            nwConnection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startTime
                    let latency = max(1, Int((Double(elapsedNanoseconds) / 1_000_000).rounded()))
                    finish(isReachable: true, latencyMilliseconds: latency, failureSummary: nil)
                case .failed(let error):
                    finish(isReachable: false, latencyMilliseconds: nil, failureSummary: Self.summarizedConnectionFailure(error))
                default:
                    break
                }
            }

            nwConnection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .seconds(tcpTimeoutSeconds)) {
                finish(isReachable: false, latencyMilliseconds: nil, failureSummary: "Timed out")
            }
        }
    }

    private nonisolated static func summarizedConnectionFailure(_ error: NWError) -> String {
        switch error {
        case .dns:
            return "DNS resolution failed"
        case .posix(let code):
            if code == .ECONNREFUSED {
                return "Connection refused"
            }
            if code == .ETIMEDOUT {
                return "Timed out"
            }
            let message = String(describing: code).trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "TCP probe failed" : message
        default:
            let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.localizedCaseInsensitiveContains("timed out") {
                return "Timed out"
            }
            return message.isEmpty ? "TCP probe failed" : message
        }
    }

    private nonisolated static func bestObservedLatency(_ values: [Int]) -> Int {
        values.min() ?? 0
    }

    private nonisolated static func summarizedProbeFailure(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return summarizedURLErrorCode(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return summarizedURLErrorCode(URLError.Code(rawValue: nsError.code))
        }

        if nsError.domain == kCFErrorDomainCFNetwork as String {
            return "Network error"
        }

        if let probeError = error as? ProbeError {
            switch probeError {
            case .invalidResponse:
                return "Invalid probe response"
            case .httpStatus(let statusCode):
                if statusCode == 401 || statusCode == 403 {
                    return "Probe blocked"
                }
                if (500 ... 599).contains(statusCode) {
                    return "Server error"
                }
                return "Probe request failed"
            }
        }

        return summarizedRuntimeFailure(error.localizedDescription)
    }

    private nonisolated static func summarizedRuntimeFailure(_ message: String) -> String {
        let firstLine = message
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if firstLine.contains("timed out") {
            return "Timed out"
        }
        if firstLine.contains("tls") || firstLine.contains("certificate") || firstLine.contains("ssl") {
            return "TLS handshake failed"
        }
        if firstLine.contains("dns") || firstLine.contains("no such host") {
            return "DNS resolution failed"
        }
        if firstLine.contains("refused") {
            return "Connection refused"
        }
        if firstLine.contains("network") {
            return "Network error"
        }
        if firstLine.contains("forbidden") || firstLine.contains("blocked") {
            return "Probe blocked"
        }
        if firstLine.contains("invalid") {
            return "Invalid probe response"
        }

        return "Probe failed"
    }

    private nonisolated static func summarizedURLErrorCode(_ code: URLError.Code) -> String {
        switch code {
        case .unknown:
            return "Network error"
        default:
            break
        }

        switch code {
        case .appTransportSecurityRequiresSecureConnection:
            return "Probe blocked"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
            return "TLS handshake failed"
        case .timedOut:
            return "Timed out"
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return "Network error"
        case .cannotFindHost, .dnsLookupFailed:
            return "DNS resolution failed"
        case .badServerResponse:
            return "Bad server response"
        case .userAuthenticationRequired, .userCancelledAuthentication, .noPermissionsToReadFile:
            return "Probe blocked"
        default:
            return "Probe failed"
        }
    }

    enum ProbeError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Probe returned an invalid response"
            case .httpStatus(let statusCode):
                return "Probe request failed with status \(statusCode)"
            }
        }
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
    @Published private(set) var queuedHealthConnectionIDs: Set<UUID> = []

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
    // Full tunnel probes spin up temporary Xray instances; allow a wider fan-out for bulk checks.
    private let healthProbeConcurrencyLimit = 10
    private var autoRefreshTimerCancellable: AnyCancellable?
    private var pendingHealthProbeIDs: [UUID] = []
    private var pendingHealthProbeIDSet: Set<UUID> = []
    private var activeHealthProbeTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingHealthProbeResults: [UUID: ConnectionHealthProbeResult] = [:]
    private var applyHealthResultsWorkItem: DispatchWorkItem?
    private var persistWorkItem: DispatchWorkItem?
    private var savedConnectionsByID: [UUID: SavedConnection] = [:]
    private var importedConnectionsBySourceID: [UUID: [SavedConnection]] = [:]
    private var importedConnectionCountsBySourceID: [UUID: Int] = [:]
    private var subscriptionSourcesByID: [UUID: SubscriptionSource] = [:]

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
        rebuildSavedConnectionIndexes()
        rebuildSubscriptionSourceIndexes()
        normalizeSelection()
        connectionPhase = savedConnections.isEmpty ? .unconfigured : .stopped
        startAutoRefreshTimer()
        updateMenuBarAnimation()
        scheduleInitialHealthRefresh()
        restoreProxyStateFromPreviousSessionIfNeeded()
    }

    var selectedConnection: SavedConnection? {
        guard let selectedConnectionID else { return savedConnections.first }
        return savedConnectionsByID[selectedConnectionID] ?? savedConnections.first
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
        !(connectionPhase == .starting || connectionPhase == .stopping || proxyPhase == .enabling || proxyPhase == .disabling)
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
        importedConnectionsBySourceID[sourceID] ?? []
    }

    func importedConnectionCount(for sourceID: UUID) -> Int {
        importedConnectionCountsBySourceID[sourceID] ?? 0
    }

    func subscriptionSource(for connection: SavedConnection) -> SubscriptionSource? {
        guard let sourceID = connection.source?.subscriptionSourceID else { return nil }
        return subscriptionSourcesByID[sourceID]
    }

    func isRefreshingSubscription(_ sourceID: UUID) -> Bool {
        refreshingSubscriptionIDs.contains(sourceID)
    }

    func isRefreshingHealth(for connectionID: UUID) -> Bool {
        refreshingHealthConnectionIDs.contains(connectionID)
    }

    func isQueuedHealth(for connectionID: UUID) -> Bool {
        queuedHealthConnectionIDs.contains(connectionID)
    }

    func healthCheck(for connection: SavedConnection) -> ConnectionHealthCheck {
        if refreshingHealthConnectionIDs.contains(connection.id) {
            var checking = connection.healthCheck ?? .unknown
            checking.state = .checking
            return checking
        }

        if queuedHealthConnectionIDs.contains(connection.id) {
            var queued = connection.healthCheck ?? .unknown
            queued.state = .queued
            return queued
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
                switch healthCheck.latencyKind {
                case .proxyRequest:
                    return "Ping \(latency) ms"
                case .tcpConnect, nil:
                    return "TCP \(latency) ms"
                }
            }
            return "Available"
        case .unreachable:
            return healthCheck.failureSummary ?? "Unavailable"
        case .queued:
            return "Queued…"
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

        if selectedConnectionID == id && hasActiveConnectionSession {
            lastError = "Disconnect before removing the active connection"
            return
        }

        let removedConnection = savedConnections.remove(at: index)
        rebuildSavedConnectionIndexes()
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

        if hasActiveConnectionSession,
           affectedConnections.contains(where: { $0.id == selectedConnectionID }) {
            lastError = "Disconnect before removing the active subscription"
            return
        }

        savedConnections.removeAll { $0.source?.subscriptionSourceID == id }
        subscriptionSources.removeAll { $0.id == id }
        rebuildSavedConnectionIndexes()
        rebuildSubscriptionSourceIndexes()
        refreshingSubscriptionIDs.remove(id)
        let removedIDs = Set(affectedConnections.map(\.id))
        cancelHealthProbes(ids: removedIDs)
        normalizeSelection()
        lastError = nil
        persistSettingError()
    }

    func selectConnection(id: UUID) {
        guard savedConnectionsByID[id] != nil else { return }

        let previousSelectionID = selectedConnectionID
        let shouldReconnect = previousSelectionID != id && hasEstablishedConnection

        if !canChangeSelection, previousSelectionID != id {
            lastError = "Please wait for the current connection action to finish"
            return
        }

        selectedConnectionID = id
        if selectedConfiguration != nil, connectionPhase == .unconfigured {
            connectionPhase = .stopped
        }
        lastError = nil
        persistSettingError()
        enqueueHealthProbes(for: [id], force: false, priority: true)

        if shouldReconnect {
            reconnectToSelectedConnection()
        }
    }

    func refreshSubscription(id: UUID) {
        refreshSubscription(id: id, autoSelectFirstImported: false)
    }

    func updateSubscriptionSettings(id: UUID, customName: String, urlString: String, autoUpdateIntervalMinutes: Int?, filterDuplicateImports: Bool) {
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
                source.filterDuplicateImports = filterDuplicateImports
                if urlChanged {
                    source.lastError = nil
                    source.lastRefreshedAt = nil
                    source.lastSkippedCount = 0
                }
            }

            if urlChanged {
                savedConnections.removeAll { $0.source?.subscriptionSourceID == id }
                rebuildSavedConnectionIndexes()
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

        startConnection(using: selectedConfiguration)
    }

    func disconnect() {
        stopConnectionForUserInitiatedDisconnect()
    }

    func handleAppTermination() {
        teardownConnection(resetError: true)
    }

    private func restoreProxyStateFromPreviousSessionIfNeeded() {
        guard proxyService.hasSavedProxySnapshot() else { return }

        let proxyService = proxyService
        operationQueue.async { [weak self] in
            do {
                try proxyService.restoreSavedProxyState()

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
    }

    private var hasEstablishedConnection: Bool {
        connectionPhase == .running || proxyPhase == .enabled
    }

    private var hasActiveConnectionSession: Bool {
        connectionPhase == .running
            || connectionPhase == .starting
            || connectionPhase == .stopping
            || connectionPhase == .failed
            || proxyPhase == .enabled
            || proxyPhase == .enabling
            || proxyPhase == .disabling
            || proxyPhase == .failed
    }

    private func reconnectToSelectedConnection() {
        guard let selectedConfiguration else {
            connectionPhase = .unconfigured
            lastError = "Add and select a connection first"
            return
        }

        let proxyEndpoint = proxyEndpoint
        let runtimeManager = runtimeManager
        let proxyService = proxyService
        let shouldDisableProxy = shouldManageSystemProxy

        connectionPhase = .stopping
        proxyPhase = .disabling
        lastError = nil
        updateMenuBarAnimation()

        operationQueue.async { [weak self] in
            do {
                if shouldDisableProxy {
                    try proxyService.disableProxy()
                }

                runtimeManager.stop()

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .starting
                    self?.proxyPhase = .enabling
                    self?.updateMenuBarAnimation()
                }

                let configURL = try XrayConfigurationWriter(proxyEndpoint: proxyEndpoint).writeConfig(for: selectedConfiguration)
                try runtimeManager.start(configURL: configURL)
                guard runtimeManager.waitUntilLocalProxyReady(endpoint: proxyEndpoint) else {
                    let detail = runtimeManager.capturedErrorOutput()?.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw XrayRuntimeManager.RuntimeError.startupTimedOut(detail)
                }
                try proxyService.enableProxy(endpoint: proxyEndpoint)

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .running
                    self?.proxyPhase = .enabled
                    self?.lastError = nil
                    self?.updateMenuBarAnimation()
                }
            } catch {
                runtimeManager.stop()
                try? proxyService.restoreSavedProxyState()

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .failed
                    self?.proxyPhase = .failed
                    self?.lastError = error.localizedDescription
                    self?.updateMenuBarAnimation()
                }
            }
        }
    }

    private func startConnection(using configuration: ConnectionConfiguration) {
        let proxyEndpoint = proxyEndpoint
        let runtimeManager = runtimeManager
        let proxyService = proxyService

        connectionPhase = .starting
        proxyPhase = .enabling
        lastError = nil
        updateMenuBarAnimation()

        operationQueue.async { [weak self] in
            do {
                let configURL = try XrayConfigurationWriter(proxyEndpoint: proxyEndpoint).writeConfig(for: configuration)
                try runtimeManager.start(configURL: configURL)
                guard runtimeManager.waitUntilLocalProxyReady(endpoint: proxyEndpoint) else {
                    let detail = runtimeManager.capturedErrorOutput()?.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw XrayRuntimeManager.RuntimeError.startupTimedOut(detail)
                }
                try proxyService.enableProxy(endpoint: proxyEndpoint)

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .running
                    self?.proxyPhase = .enabled
                    self?.lastError = nil
                    self?.updateMenuBarAnimation()
                }
            } catch {
                runtimeManager.stop()
                try? proxyService.restoreSavedProxyState()

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .failed
                    self?.proxyPhase = .failed
                    self?.lastError = error.localizedDescription
                    self?.updateMenuBarAnimation()
                }
            }
        }
    }

    private var shouldManageSystemProxy: Bool {
        proxyPhase == .enabled || proxyPhase == .enabling || proxyPhase == .failed || proxyPhase == .disabling
    }

    private func stopConnectionForUserInitiatedDisconnect() {
        let shouldDisableProxy = shouldManageSystemProxy
        let hasSavedConfiguration = selectedConfiguration != nil
        let runtimeManager = runtimeManager
        let proxyService = proxyService

        connectionPhase = .stopping
        proxyPhase = .disabling
        updateMenuBarAnimation()

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

    private func addManualConnection(from rawLink: String) -> Bool {
        do {
            let configuration = try parser.parse(rawLink)
            let savedConnection = SavedConnection(id: UUID(), configuration: configuration, savedAt: Date(), source: nil)
            savedConnections.append(savedConnection)
            rebuildSavedConnectionIndexes()
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
                autoUpdateIntervalMinutes: nil,
                filterDuplicateImports: true
            )

            subscriptionSources.append(source)
            rebuildSubscriptionSourceIndexes()
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

        if hasActiveConnectionSession,
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
                let importResult = try Self.importSubscriptionEntries(
                    links: links,
                    parser: parser,
                    sourceID: source.id,
                    filterDuplicateImports: source.filterDuplicateImports
                )

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

    nonisolated static func importSubscriptionEntries(
        links: [String],
        parser: ConnectionLinkParser,
        sourceID: UUID,
        filterDuplicateImports: Bool
    ) throws -> SubscriptionImportResult {
        var importedEntries: [ImportedSubscriptionEntry] = []
        var skippedCount = 0
        var seenDuplicateKeys: Set<String> = []

        for rawLink in links {
            do {
                let configuration = try parser.parse(rawLink)
                let sourceEntryID = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)

                if filterDuplicateImports {
                    let duplicateKey = configuration.duplicateFilterIdentity
                    guard seenDuplicateKeys.insert(duplicateKey).inserted else {
                        continue
                    }
                }

                importedEntries.append(
                    ImportedSubscriptionEntry(
                        sourceEntryID: sourceEntryID,
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
        rebuildSavedConnectionIndexes()
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

        var prioritizedIDs: [UUID] = []

        for id in ids {
            guard let connection = savedConnectionsByID[id] else { continue }
            guard force || needsHealthRefresh(for: connection) else { continue }
            guard activeHealthProbeTasks[id] == nil else { continue }
            guard !pendingHealthProbeIDSet.contains(id) else { continue }

            if priority {
                prioritizedIDs.append(id)
            } else {
                pendingHealthProbeIDs.append(id)
            }
            pendingHealthProbeIDSet.insert(id)
        }

        queuedHealthConnectionIDs = pendingHealthProbeIDSet

        if priority, !prioritizedIDs.isEmpty {
            pendingHealthProbeIDs.insert(contentsOf: prioritizedIDs, at: 0)
        }

        drainHealthProbeQueue()
    }

    private func drainHealthProbeQueue() {
        while activeHealthProbeTasks.count < healthProbeConcurrencyLimit,
              let nextID = pendingHealthProbeIDs.first {
            pendingHealthProbeIDs.removeFirst()
            pendingHealthProbeIDSet.remove(nextID)
            queuedHealthConnectionIDs = pendingHealthProbeIDSet

            guard let connection = savedConnectionsByID[nextID] else {
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
                latencyKind: result.latencyKind,
                failureSummary: result.failureSummary
            )
        }

        rebuildSavedConnectionIndexes()
        schedulePersist()
    }

    private func cancelHealthProbe(id: UUID) {
        activeHealthProbeTasks[id]?.cancel()
        activeHealthProbeTasks[id] = nil
        refreshingHealthConnectionIDs.remove(id)
        pendingHealthProbeIDSet.remove(id)
        queuedHealthConnectionIDs = pendingHealthProbeIDSet
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
        subscriptionSourcesByID[id] = subscriptionSources[index]
    }

    private func rebuildSavedConnectionIndexes() {
        savedConnectionsByID = Dictionary(uniqueKeysWithValues: savedConnections.map { ($0.id, $0) })

        let groupedImportedConnections = Dictionary(grouping: savedConnections) { connection in
            connection.source?.subscriptionSourceID
        }

        importedConnectionsBySourceID = groupedImportedConnections.reduce(into: [:]) { partialResult, item in
            guard let sourceID = item.key else { return }
            partialResult[sourceID] = item.value.sorted {
                $0.configuration.displayName.localizedCaseInsensitiveCompare($1.configuration.displayName) == .orderedAscending
            }
        }

        importedConnectionCountsBySourceID = importedConnectionsBySourceID.reduce(into: [:]) { partialResult, item in
            partialResult[item.key] = item.value.count
        }
    }

    private func rebuildSubscriptionSourceIndexes() {
        subscriptionSourcesByID = Dictionary(uniqueKeysWithValues: subscriptionSources.map { ($0.id, $0) })
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
        // Animation timing is owned by MenuBarIconView. Keeping this hook avoids
        // broad call-site churn while preventing high-frequency AppViewModel
        // publications that re-render the entire menu/settings UI while connected.
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
