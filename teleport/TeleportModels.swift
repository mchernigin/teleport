import Foundation

enum ConnectionPhase: String, Codable {
    case unconfigured
    case ready
    case starting
    case running
    case stopping
    case stopped
    case failed
}

enum ProxyPhase: String, Codable {
    case disabled
    case enabling
    case enabled
    case disabling
    case failed
}

struct ProxyEndpoint: Codable, Equatable {
    let host: String
    let httpPort: Int
    let socksPort: Int

    static let `default` = ProxyEndpoint(host: "127.0.0.1", httpPort: 8080, socksPort: 1080)
}

enum ConnectionProtocolType: String, Codable, CaseIterable {
    case vless
    case trojan

    var displayName: String {
        rawValue.uppercased()
    }
}

enum ConnectionTransport: String, Codable, CaseIterable {
    case tcp
    case ws
}

enum ConnectionSecurity: String, Codable, CaseIterable {
    case none
    case tls
    case reality
}

struct ConnectionConfiguration: Codable, Equatable {
    let rawLink: String
    let protocolType: ConnectionProtocolType
    let host: String
    let port: Int
    let remarks: String?
    let security: ConnectionSecurity
    let transport: ConnectionTransport
    let path: String?
    let hostHeader: String?
    let serverName: String?
    let alpn: [String]
    let fingerprint: String?
    let publicKey: String?
    let shortID: String?
    let spiderX: String?
    let vlessUserID: String?
    let vlessFlow: String?
    let trojanPassword: String?

    var displayName: String {
        if let remarks, !remarks.isEmpty {
            return remarks
        }
        return "\(host):\(port)"
    }

    var endpointSummary: String {
        "\(host):\(port)"
    }
}

struct ConnectionSourceMetadata: Codable, Equatable {
    let subscriptionSourceID: UUID
    let subscriptionEntryID: String
}

struct SavedConnection: Codable, Equatable, Identifiable {
    let id: UUID
    let configuration: ConnectionConfiguration
    let savedAt: Date
    let source: ConnectionSourceMetadata?

    var isImported: Bool {
        source != nil
    }

    init(id: UUID, configuration: ConnectionConfiguration, savedAt: Date, source: ConnectionSourceMetadata? = nil) {
        self.id = id
        self.configuration = configuration
        self.savedAt = savedAt
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case configuration
        case savedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        configuration = try container.decode(ConnectionConfiguration.self, forKey: .configuration)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        source = try container.decodeIfPresent(ConnectionSourceMetadata.self, forKey: .source)
    }
}

struct SubscriptionSource: Codable, Equatable, Identifiable {
    let id: UUID
    var urlString: String
    var title: String
    let savedAt: Date
    var autoUpdateIntervalMinutes: Int?
    var lastRefreshedAt: Date?
    var lastError: String?
    var lastSkippedCount: Int

    var displayName: String {
        if !title.isEmpty {
            return title
        }

        if let url = URL(string: urlString), let host = url.host, !host.isEmpty {
            return host
        }

        return urlString
    }

    init(
        id: UUID,
        urlString: String,
        title: String,
        savedAt: Date,
        autoUpdateIntervalMinutes: Int? = nil,
        lastRefreshedAt: Date? = nil,
        lastError: String? = nil,
        lastSkippedCount: Int = 0
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.savedAt = savedAt
        self.autoUpdateIntervalMinutes = autoUpdateIntervalMinutes
        self.lastRefreshedAt = lastRefreshedAt
        self.lastError = lastError
        self.lastSkippedCount = lastSkippedCount
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case urlString
        case title
        case savedAt
        case autoUpdateIntervalMinutes
        case lastRefreshedAt
        case lastError
        case lastSkippedCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        urlString = try container.decode(String.self, forKey: .urlString)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        autoUpdateIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .autoUpdateIntervalMinutes)
        lastRefreshedAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshedAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        lastSkippedCount = try container.decodeIfPresent(Int.self, forKey: .lastSkippedCount) ?? 0
    }
}

struct AppSnapshot: Codable, Equatable {
    var savedConnections: [SavedConnection]
    var subscriptionSources: [SubscriptionSource]
    var selectedConnectionID: UUID?
    var proxyEndpoint: ProxyEndpoint

    init(
        savedConnections: [SavedConnection],
        subscriptionSources: [SubscriptionSource] = [],
        selectedConnectionID: UUID?,
        proxyEndpoint: ProxyEndpoint
    ) {
        self.savedConnections = savedConnections
        self.subscriptionSources = subscriptionSources
        self.selectedConnectionID = selectedConnectionID
        self.proxyEndpoint = proxyEndpoint
    }

    private enum CodingKeys: String, CodingKey {
        case savedConnections
        case subscriptionSources
        case selectedConnectionID
        case proxyEndpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedConnections = try container.decodeIfPresent([SavedConnection].self, forKey: .savedConnections) ?? []
        subscriptionSources = try container.decodeIfPresent([SubscriptionSource].self, forKey: .subscriptionSources) ?? []
        selectedConnectionID = try container.decodeIfPresent(UUID.self, forKey: .selectedConnectionID)
        proxyEndpoint = try container.decodeIfPresent(ProxyEndpoint.self, forKey: .proxyEndpoint) ?? .default
    }
}

enum ConfigurationError: LocalizedError, Equatable {
    case invalidScheme
    case missingHost
    case invalidPort
    case missingUser
    case missingPassword
    case invalidUUID
    case unsupportedTransport(String)
    case unsupportedSecurity(String)
    case unsupportedFlow(String)
    case missingParameter(String)
    case malformedQuery

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "Connection link must start with vless:// or trojan://"
        case .missingHost:
            return "Server host is missing"
        case .invalidPort:
            return "Port is missing or invalid"
        case .missingUser:
            return "Required user component is missing"
        case .missingPassword:
            return "Trojan password is missing"
        case .invalidUUID:
            return "VLESS user id must be a valid UUID"
        case let .unsupportedTransport(value):
            return "Unsupported transport for this release: \(value)"
        case let .unsupportedSecurity(value):
            return "Unsupported security for this release: \(value)"
        case let .unsupportedFlow(value):
            return "Unsupported flow for this release: \(value)"
        case let .missingParameter(name):
            return "Missing required parameter: \(name)"
        case .malformedQuery:
            return "The connection link contains malformed query parameters"
        }
    }
}

enum SubscriptionError: LocalizedError, Equatable {
    case invalidURL
    case duplicateSource
    case networkFailure(String)
    case invalidResponse
    case emptyPayload
    case noSupportedEntries

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Subscription URL must start with http:// or https://"
        case .duplicateSource:
            return "This subscription has already been added"
        case let .networkFailure(message):
            return message.isEmpty ? "Failed to fetch subscription" : message
        case .invalidResponse:
            return "Subscription server returned an invalid response"
        case .emptyPayload:
            return "Subscription did not contain any links"
        case .noSupportedEntries:
            return "Subscription does not contain any supported VLESS or Trojan links"
        }
    }
}

struct LegacyVLESSConfiguration: Codable, Equatable {
    let rawLink: String
    let id: UUID
    let userID: String
    let host: String
    let port: Int
    let remarks: String?
    let security: ConnectionSecurity
    let transport: ConnectionTransport
    let flow: String?
    let path: String?
    let serverName: String?
    let alpn: [String]
    let fingerprint: String?
    let publicKey: String?
    let shortID: String?
    let spiderX: String?
}

struct LegacyPersistedConfiguration: Codable, Equatable {
    let configuration: LegacyVLESSConfiguration
    let savedAt: Date
}

struct LegacyAppSnapshot: Codable, Equatable {
    var persistedConfiguration: LegacyPersistedConfiguration?
    var proxyEndpoint: ProxyEndpoint
}

extension LegacyVLESSConfiguration {
    var asConnectionConfiguration: ConnectionConfiguration {
        ConnectionConfiguration(
            rawLink: rawLink,
            protocolType: .vless,
            host: host,
            port: port,
            remarks: remarks,
            security: security,
            transport: transport,
            path: path,
            hostHeader: nil,
            serverName: serverName,
            alpn: alpn,
            fingerprint: fingerprint,
            publicKey: publicKey,
            shortID: shortID,
            spiderX: spiderX,
            vlessUserID: userID,
            vlessFlow: flow,
            trojanPassword: nil
        )
    }
}

extension LegacyAppSnapshot {
    var asAppSnapshot: AppSnapshot {
        let savedConnections = persistedConfiguration.map {
            [
                SavedConnection(
                    id: $0.configuration.id,
                    configuration: $0.configuration.asConnectionConfiguration,
                    savedAt: $0.savedAt,
                    source: nil
                )
            ]
        } ?? []

        return AppSnapshot(
            savedConnections: savedConnections,
            subscriptionSources: [],
            selectedConnectionID: savedConnections.first?.id,
            proxyEndpoint: proxyEndpoint
        )
    }
}
