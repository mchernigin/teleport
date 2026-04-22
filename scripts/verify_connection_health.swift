import Foundation

@main
struct VerifyConnectionHealth {
    static func main() throws {
        try testHealthMetadataSnapshotRoundTrip()
        try testLegacySnapshotWithoutHealthMetadata()
        try testFreshnessClassification()
        try testSubscriptionRefreshPreservesHealthForEquivalentEntry()
        print("verify_connection_health: all checks passed")
    }

    private static func testHealthMetadataSnapshotRoundTrip() throws {
        let parser = ConnectionLinkParser()
        let connection = SavedConnection(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            configuration: try parser.parse(sampleVLESSLink()),
            savedAt: Date(timeIntervalSince1970: 100),
            source: nil,
            healthCheck: ConnectionHealthCheck(
                state: .reachable,
                checkedAt: Date(timeIntervalSince1970: 200),
                latencyMilliseconds: 42,
                failureSummary: nil
            )
        )
        let snapshot = AppSnapshot(
            savedConnections: [connection],
            subscriptionSources: [],
            selectedConnectionID: connection.id,
            proxyEndpoint: .default
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)

        precondition(decoded.savedConnections.count == 1)
        precondition(decoded.savedConnections[0].healthCheck?.state == .reachable)
        precondition(decoded.savedConnections[0].healthCheck?.latencyMilliseconds == 42)
    }

    private static func testLegacySnapshotWithoutHealthMetadata() throws {
        let legacyJSON = """
        {
          "savedConnections": [
            {
              "id": "11111111-2222-3333-4444-555555555555",
              "configuration": {
                "rawLink": "\(sampleVLESSLink())",
                "protocolType": "vless",
                "host": "example.com",
                "port": 443,
                "remarks": "Alpha",
                "security": "tls",
                "transport": "tcp",
                "path": null,
                "hostHeader": null,
                "serverName": "example.com",
                "alpn": [],
                "fingerprint": null,
                "publicKey": null,
                "shortID": null,
                "spiderX": null,
                "vlessUserID": "123e4567-e89b-12d3-a456-426614174000",
                "vlessFlow": null,
                "trojanPassword": null
              },
              "savedAt": 100
            }
          ],
          "subscriptionSources": [],
          "selectedConnectionID": "11111111-2222-3333-4444-555555555555",
          "proxyEndpoint": {
            "host": "127.0.0.1",
            "httpPort": 8080,
            "socksPort": 1080
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: legacyJSON)
        precondition(decoded.savedConnections.count == 1)
        precondition(decoded.savedConnections[0].healthCheck == nil)
    }

    private static func testFreshnessClassification() throws {
        let fresh = ConnectionHealthCheck(
            state: .reachable,
            checkedAt: Date(),
            latencyMilliseconds: 12,
            failureSummary: nil
        )
        precondition(fresh.freshness(now: Date(), ttl: 60) == .fresh)

        let stale = ConnectionHealthCheck(
            state: .unreachable,
            checkedAt: Date(timeIntervalSinceNow: -3600),
            latencyMilliseconds: nil,
            failureSummary: "Timed out"
        )
        precondition(stale.freshness(now: Date(), ttl: 60) == .stale)

        precondition(ConnectionHealthCheck.unknown.freshness(now: Date(), ttl: 60) == .unknown)
    }

    private static func testSubscriptionRefreshPreservesHealthForEquivalentEntry() throws {
        let parser = ConnectionLinkParser()
        let sourceID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let sourceEntry = sampleVLESSLink()
        let existing = SavedConnection(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            configuration: try parser.parse(sourceEntry),
            savedAt: Date(timeIntervalSince1970: 100),
            source: ConnectionSourceMetadata(subscriptionSourceID: sourceID, subscriptionEntryID: sourceEntry),
            healthCheck: ConnectionHealthCheck(
                state: .reachable,
                checkedAt: Date(timeIntervalSince1970: 200),
                latencyMilliseconds: 34,
                failureSummary: nil
            )
        )

        let reconciled = SubscriptionConnectionReconciler().reconcile(
            existingConnections: [existing],
            sourceID: sourceID,
            selectedConnectionID: existing.id,
            importedEntries: [
                ImportedSubscriptionEntry(
                    sourceEntryID: sourceEntry,
                    configuration: try parser.parse(sourceEntry)
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 300),
            autoSelectFirstImported: false
        )

        precondition(reconciled.savedConnections.count == 1)
        precondition(reconciled.savedConnections[0].healthCheck?.latencyMilliseconds == 34)
        precondition(reconciled.selectedConnectionID == existing.id)
    }

    private static func sampleVLESSLink() -> String {
        "vless://123e4567-e89b-12d3-a456-426614174000@example.com:443?security=tls&type=tcp&sni=example.com#Alpha"
    }
}
