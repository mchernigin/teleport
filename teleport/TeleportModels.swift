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

struct VLESSConfiguration: Codable, Equatable {
    enum Transport: String, Codable, CaseIterable {
        case tcp
        case ws
    }

    enum Security: String, Codable, CaseIterable {
        case none
        case tls
        case reality
    }

    let rawLink: String
    let id: UUID
    let userID: String
    let host: String
    let port: Int
    let remarks: String?
    let security: Security
    let transport: Transport
    let flow: String?
    let path: String?
    let serverName: String?
    let alpn: [String]
    let fingerprint: String?
    let publicKey: String?
    let shortID: String?
    let spiderX: String?

    var displayName: String {
        if let remarks, !remarks.isEmpty {
            return remarks
        }
        return "\(host):\(port)"
    }
}

struct PersistedConfiguration: Codable, Equatable {
    let configuration: VLESSConfiguration
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
    case invalidUUID
    case unsupportedTransport(String)
    case unsupportedSecurity(String)
    case unsupportedFlow(String)
    case missingParameter(String)
    case malformedQuery

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "Link must start with vless://"
        case .missingHost:
            return "Server host is missing"
        case .invalidPort:
            return "Port is missing or invalid"
        case .missingUser:
            return "VLESS user id is missing"
        case .invalidUUID:
            return "VLESS user id must be a valid UUID"
        case let .unsupportedTransport(value):
            return "Unsupported transport for v1: \(value)"
        case let .unsupportedSecurity(value):
            return "Unsupported security for v1: \(value)"
        case let .unsupportedFlow(value):
            return "Unsupported flow for v1: \(value)"
        case let .missingParameter(name):
            return "Missing required parameter: \(name)"
        case .malformedQuery:
            return "The VLESS link contains malformed query parameters"
        }
    }
}
