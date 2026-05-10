import AppKit
import CFNetwork
import Combine
import Darwin
import Foundation
import Network
import Security
import SystemConfiguration

final class ConfigurationStore {
    private let fileManager: FileManager
    private let fileURL: URL
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let keychainService = "dev.x.teleport.configuration"
    private static let keychainAccount = "app-snapshot"
    private static let stateFilePlaceholder = "{\"storage\":\"keychain\",\"version\":2}\n"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = baseURL.appendingPathComponent("teleport", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        fileURL = directoryURL.appendingPathComponent("state.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var hasSavedSnapshot: Bool {
        keychainSnapshotData() != nil || fileManager.fileExists(atPath: fileURL.path)
    }

    func load() -> AppSnapshot {
        if let data = keychainSnapshotData(), let snapshot = decodeSnapshot(from: data) {
            return snapshot
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return AppSnapshot(savedConnections: [], subscriptionSources: [], selectedConnectionID: nil, proxyEndpoint: .default)
        }

        if let snapshot = decodeSnapshot(from: data) {
            try? save(snapshot)
            return snapshot
        }

        return AppSnapshot(savedConnections: [], subscriptionSources: [], selectedConnectionID: nil, proxyEndpoint: .default)
    }

    func save(_ snapshot: AppSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try saveKeychainSnapshotData(data)
        try writeStatePlaceholder()
    }

    private func decodeSnapshot(from data: Data) -> AppSnapshot? {
        if let snapshot = try? decoder.decode(AppSnapshot.self, from: data) {
            return snapshot
        }

        if let legacySnapshot = try? decoder.decode(LegacyAppSnapshot.self, from: data) {
            return legacySnapshot.asAppSnapshot
        }

        return nil
    }

    private func writeStatePlaceholder() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        try Data(Self.stateFilePlaceholder.utf8).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    private func keychainSnapshotData() -> Data? {
        var query = keychainBaseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func saveKeychainSnapshotData(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(keychainBaseQuery() as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw ConfigurationStoreError.keychainWriteFailed(updateStatus)
        }

        var addQuery = keychainBaseQuery()
        addQuery.merge(attributes) { _, new in new }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ConfigurationStoreError.keychainWriteFailed(addStatus)
        }
    }

    private func keychainBaseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
    }
}

enum ConfigurationStoreError: LocalizedError {
    case keychainWriteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .keychainWriteFailed(status):
            return "Failed to save Teleport configuration secrets to Keychain: OSStatus \(status)"
        }
    }
}
