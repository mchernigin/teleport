import AppKit
import CFNetwork
import Combine
import Darwin
import Foundation
import Network
import SystemConfiguration

final class AppViewModel: ObservableObject {
    @Published private(set) var savedConnections: [SavedConnection]
    @Published private(set) var subscriptionSources: [SubscriptionSource]
    @Published private(set) var selectedConnectionID: UUID?
    @Published private(set) var connectionPhase: ConnectionPhase = .unconfigured
    @Published private(set) var proxyPhase: ProxyPhase = .disabled
    @Published private(set) var lastError: String?
    @Published private(set) var lastErrorDetails: String?
    @Published private(set) var proxyEndpoint: ProxyEndpoint
    @Published private(set) var connectionMode: ConnectionMode
    @Published private(set) var refreshingSubscriptionIDs: Set<UUID> = []
    @Published private(set) var refreshingHealthConnectionIDs: Set<UUID> = []
    @Published private(set) var queuedHealthConnectionIDs: Set<UUID> = []

    private let parser: ConnectionLinkParser
    private let store: ConfigurationStore
    private let connectionBackendFactory: ConnectionBackendFactory
    private var connectionBackend: ConnectionBackend
    private let subscriptionClient: SubscriptionClient
    private let healthProbeService: ConnectionHealthProbeService
    private let operationQueue = DispatchQueue(label: "dev.x.teleport.connection-operations", qos: .userInitiated)
    private let persistenceQueue = DispatchQueue(label: "dev.x.teleport.persistence", qos: .utility)
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
            connectionBackendFactory: ConnectionBackendFactory(),
            subscriptionClient: SubscriptionClient(),
            healthProbeService: ConnectionHealthProbeService()
        )
    }

    init(
        parser: ConnectionLinkParser,
        store: ConfigurationStore,
        connectionBackendFactory: ConnectionBackendFactory,
        subscriptionClient: SubscriptionClient,
        healthProbeService: ConnectionHealthProbeService
    ) {
        self.parser = parser
        self.store = store
        self.connectionBackendFactory = connectionBackendFactory
        self.subscriptionClient = subscriptionClient
        self.healthProbeService = healthProbeService

        let snapshot = store.load()
        connectionMode = snapshot.connectionMode
        connectionBackend = connectionBackendFactory.makeBackend(for: snapshot.connectionMode)
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

    var hasActiveConnectionSession: Bool {
        connectionPhase == .running
            || connectionPhase == .starting
            || connectionPhase == .stopping
            || connectionPhase == .failed
            || proxyPhase == .enabled
            || proxyPhase == .enabling
            || proxyPhase == .disabling
            || proxyPhase == .failed
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

        return connection.healthCheck ?? .unknown
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
            setStoredError("Paste a connection or subscription URL first")
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
            setStoredError("Disconnect before removing the active connection")
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
        updateIdleConnectionPhaseIfNeeded()

        setStoredError(nil)
        persistSettingError()
    }

    func removeSubscription(id: UUID) {
        let affectedConnections = importedConnections(for: id)

        if hasActiveConnectionSession,
           affectedConnections.contains(where: { $0.id == selectedConnectionID }) {
            setStoredError("Disconnect before removing the active subscription")
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
        updateIdleConnectionPhaseIfNeeded()
        setStoredError(nil)
        persistSettingError()
    }

    func selectConnection(id: UUID) {
        guard savedConnectionsByID[id] != nil else { return }

        let previousSelectionID = selectedConnectionID
        let shouldReconnect = previousSelectionID != id && hasEstablishedConnection

        if !canChangeSelection, previousSelectionID != id {
            setStoredError("Please wait for the current connection action to finish")
            return
        }

        selectedConnectionID = id
        if selectedConfiguration != nil, connectionPhase == .unconfigured {
            connectionPhase = .stopped
        }
        setStoredError(nil)
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
            let selectedConnectionSourceID = selectedConnectionID.flatMap { savedConnectionsByID[$0] }?.source?.subscriptionSourceID
            let selectionBelongsToUpdatedSource = selectedConnectionSourceID == id

            if urlChanged,
               hasActiveConnectionSession,
               selectionBelongsToUpdatedSource {
                setStoredError("Disconnect before changing the active subscription URL")
                return
            }

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
                if selectionBelongsToUpdatedSource {
                    normalizeSelection()
                }
                updateIdleConnectionPhaseIfNeeded()
            }

            setStoredError(nil)
            persistSettingError()

            if urlChanged {
                refreshSubscription(id: id, autoSelectFirstImported: false)
            }
        } catch {
            setStoredError(error.localizedDescription)
        }
    }

    func clearError() {
        setStoredError(nil)
    }

    func selectConnectionMode(_ mode: ConnectionMode) {
        guard mode != connectionMode else { return }
        guard canChangeSelection && !hasActiveConnectionSession else {
            setStoredError("Disconnect before changing connection mode")
            return
        }

        connectionBackend.teardown()
        connectionMode = mode
        connectionBackend = connectionBackendFactory.makeBackend(for: mode)
        proxyPhase = .disabled
        connectionPhase = savedConnections.isEmpty ? .unconfigured : .stopped
        setStoredError(nil)
        updateMenuBarAnimation()
        persistSettingError()
    }

    func connect() {
        guard let selectedConfiguration else {
            connectionPhase = .unconfigured
            setStoredError("Add and select a connection first")
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
        guard connectionBackend.hasRestorableState() else { return }

        let connectionBackend = connectionBackend
        operationQueue.async { [weak self] in
            do {
                try connectionBackend.restorePreviousState()

                Task { @MainActor [weak self] in
                    self?.proxyPhase = .disabled
                    self?.setStoredError(nil)
                    self?.updateMenuBarAnimation()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.proxyPhase = .failed
                    self?.applyConnectionError(error)
                    self?.updateMenuBarAnimation()
                }
            }
        }
    }

    private var hasEstablishedConnection: Bool {
        connectionPhase == .running || proxyPhase == .enabled
    }

    private func reconnectToSelectedConnection() {
        guard let selectedConfiguration else {
            connectionPhase = .unconfigured
            setStoredError("Add and select a connection first")
            return
        }

        let proxyEndpoint = proxyEndpoint
        let connectionBackend = connectionBackend
        let shouldDisableProxy = shouldManageSystemProxy

        connectionPhase = .stopping
        proxyPhase = .disabling
        setStoredError(nil)
        updateMenuBarAnimation()

        operationQueue.async { [weak self] in
            do {
                Task { @MainActor [weak self] in
                    self?.connectionPhase = .starting
                    self?.proxyPhase = .enabling
                    self?.updateMenuBarAnimation()
                }

                try connectionBackend.reconnect(
                    configuration: selectedConfiguration,
                    endpoint: proxyEndpoint,
                    shouldDisableExistingProxy: shouldDisableProxy
                )

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .running
                    self?.proxyPhase = .enabled
                    self?.setStoredError(nil)
                    self?.updateMenuBarAnimation()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.connectionPhase = .failed
                    self?.proxyPhase = .failed
                    self?.applyConnectionError(error)
                    self?.updateMenuBarAnimation()
                }
            }
        }
    }

    private func startConnection(using configuration: ConnectionConfiguration) {
        let proxyEndpoint = proxyEndpoint
        let connectionBackend = connectionBackend

        connectionPhase = .starting
        proxyPhase = .enabling
        setStoredError(nil)
        updateMenuBarAnimation()

        operationQueue.async { [weak self] in
            do {
                try connectionBackend.start(configuration: configuration, endpoint: proxyEndpoint)

                Task { @MainActor [weak self] in
                    self?.connectionPhase = .running
                    self?.proxyPhase = .enabled
                    self?.setStoredError(nil)
                    self?.updateMenuBarAnimation()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.connectionPhase = .failed
                    self?.proxyPhase = .failed
                    self?.applyConnectionError(error)
                    self?.updateMenuBarAnimation()
                }
            }
        }
    }

    private func setStoredError(_ message: String?) {
        lastError = message
        lastErrorDetails = nil
    }

    private func applyConnectionError(_ error: Error) {
        setStoredError(error.localizedDescription)
        if let localizedError = error as? LocalizedError,
           let details = localizedError.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !details.isEmpty,
           details != lastError {
            lastErrorDetails = details
        } else {
            lastErrorDetails = nil
        }
    }

    private var shouldManageSystemProxy: Bool {
        proxyPhase == .enabled || proxyPhase == .enabling || proxyPhase == .failed || proxyPhase == .disabling
    }

    private func stopConnectionForUserInitiatedDisconnect() {
        let shouldDisableProxy = shouldManageSystemProxy
        let hasSavedConfiguration = selectedConfiguration != nil
        let connectionBackend = connectionBackend

        connectionPhase = .stopping
        proxyPhase = .disabling
        updateMenuBarAnimation()

        operationQueue.async { [weak self] in
            do {
                try connectionBackend.stop(shouldDisableProxy: shouldDisableProxy)
                Task { @MainActor [weak self] in
                    self?.connectionPhase = hasSavedConfiguration ? .stopped : .unconfigured
                    self?.proxyPhase = .disabled
                    self?.setStoredError(nil)
                    self?.updateMenuBarAnimation()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.connectionPhase = hasSavedConfiguration ? .stopped : .unconfigured
                    self?.proxyPhase = .failed
                    self?.applyConnectionError(error)
                    self?.updateMenuBarAnimation()
                }
            }
        }
    }

    private func addManualConnection(from rawLink: String) -> Bool {
        do {
            let configuration = try parser.parse(rawLink)
            let savedConnection = SavedConnection(id: UUID(), configuration: configuration, savedAt: Date(), source: nil)
            let shouldSelectNewConnection = !hasActiveConnectionSession || selectedConnectionID == nil
            savedConnections.append(savedConnection)
            rebuildSavedConnectionIndexes()
            if shouldSelectNewConnection {
                selectedConnectionID = savedConnection.id
            }
            updateIdleConnectionPhaseIfNeeded()
            setStoredError(nil)
            updateMenuBarAnimation()
            try persist()
            enqueueHealthProbes(for: [savedConnection.id], force: true, priority: true)
            return true
        } catch {
            setStoredError(error.localizedDescription)
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
            setStoredError(nil)
            persistSettingError()
            refreshSubscription(id: source.id, autoSelectFirstImported: savedConnections.isEmpty)
            return true
        } catch {
            setStoredError(error.localizedDescription)
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
            setStoredError("Disconnect before refreshing the active subscription")
            return
        }

        startSubscriptionRefresh(for: source, autoSelectFirstImported: autoSelectFirstImported)
    }

    private func startSubscriptionRefresh(for source: SubscriptionSource, autoSelectFirstImported: Bool) {
        refreshingSubscriptionIDs.insert(source.id)
        updateSubscriptionSource(source.id) {
            $0.lastError = nil
        }
        setStoredError(nil)
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
                    self?.applyConnectionError(error)
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
        let selectedConnectionSourceID = selectedConnectionID.flatMap { savedConnectionsByID[$0] }?.source?.subscriptionSourceID
        if hasActiveConnectionSession,
           selectedConnectionSourceID == sourceID {
            refreshingSubscriptionIDs.remove(sourceID)
            updateSubscriptionSource(sourceID) {
                $0.lastError = "Disconnect before refreshing the active subscription"
            }
            setStoredError("Disconnect before refreshing the active subscription")
            persistSettingError()
            return
        }

        let replacementResult = SubscriptionConnectionReconciler().reconcile(
            existingConnections: savedConnections,
            sourceID: sourceID,
            selectedConnectionID: selectedConnectionID,
            importedEntries: importedEntries,
            fetchedAt: fetchedAt,
            autoSelectFirstImported: autoSelectFirstImported
        )

        savedConnections = replacementResult.savedConnections
        invalidateHealthChecksForImportedConnections(from: sourceID)
        rebuildSavedConnectionIndexes()
        selectedConnectionID = replacementResult.selectedConnectionID

        updateSubscriptionSource(sourceID) {
            $0.lastRefreshedAt = fetchedAt
            $0.lastSkippedCount = skippedCount
            $0.lastError = skippedCount > 0 ? "Skipped \(skippedCount) unsupported entries during last refresh" : nil
        }

        refreshingSubscriptionIDs.remove(sourceID)
        setStoredError(nil)
        updateIdleConnectionPhaseIfNeeded()
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

    private func needsHealthRefresh(for connection: SavedConnection) -> Bool {
        guard let healthCheck = connection.healthCheck else {
            return true
        }

        switch healthCheck.state {
        case .unknown, .queued, .checking:
            return true
        case .reachable, .unreachable:
            return false
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

    private func invalidateHealthChecksForImportedConnections(from sourceID: UUID) {
        for index in savedConnections.indices
        where savedConnections[index].source?.subscriptionSourceID == sourceID {
            savedConnections[index].healthCheck = nil
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

    private func updateIdleConnectionPhaseIfNeeded() {
        guard !hasActiveConnectionSession else { return }
        connectionPhase = savedConnections.isEmpty ? .unconfigured : .stopped
    }

    private func teardownConnection(resetError: Bool) {
        connectionBackend.teardown()
        connectionPhase = selectedConfiguration == nil ? .unconfigured : .stopped
        proxyPhase = .disabled
        if resetError {
            setStoredError(nil)
        }
        updateMenuBarAnimation()
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
            setStoredError(error.localizedDescription)
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
                    self?.applyConnectionError(error)
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
            proxyEndpoint: proxyEndpoint,
            connectionMode: connectionMode
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
