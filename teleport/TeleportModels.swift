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

struct PersistedConfiguration: Codable, Equatable {
    let configuration: ConnectionConfiguration
    let savedAt: Date
}

struct AppSnapshot: Codable, Equatable {
    var persistedConfiguration: PersistedConfiguration?
    var proxyEndpoint: ProxyEndpoint
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
        AppSnapshot(
            persistedConfiguration: persistedConfiguration.map {
                PersistedConfiguration(configuration: $0.configuration.asConnectionConfiguration, savedAt: $0.savedAt)
            },
            proxyEndpoint: proxyEndpoint
        )
    }
}
