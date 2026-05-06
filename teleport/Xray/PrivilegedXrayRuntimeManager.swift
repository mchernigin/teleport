import Foundation

final class PrivilegedXrayRuntimeManager: @unchecked Sendable {
    private let bundle: Bundle
    private let fileManager: FileManager
    private let paths: XrayTunRuntimePaths
    private let helperClient: PrivilegedHelperClient
    private let helperInstaller: PrivilegedHelperInstaller

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        helperClient: PrivilegedHelperClient = PrivilegedHelperClient(),
        helperInstaller: PrivilegedHelperInstaller? = nil
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
        self.paths = XrayTunRuntimePaths(fileManager: fileManager)
        self.helperClient = helperClient
        self.helperInstaller = helperInstaller ?? PrivilegedHelperInstaller(bundle: bundle)
    }

    func runtimeURL() -> URL? {
        bundle.url(forResource: "xray", withExtension: nil)
    }

    func start(session: XrayTunLaunchSession) throws {
        try fileManager.createDirectory(at: paths.stateDirectoryURL, withIntermediateDirectories: true)

        guard let runtimeURL = runtimeURL() else {
            throw XrayRuntimeManager.RuntimeError.binaryNotFound
        }

        do {
            try helperInstaller.ensureInstalled(runtimeURL: runtimeURL)
            try helperClient.start(session: session, paths: paths)
            try persistSessionState(for: session)
        } catch {
            throw XrayTunRuntimeError.startFailed(summary: readableSummary(from: error), details: diagnosticDetails(from: error))
        }
    }

    func waitUntilRunning(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isRunning() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    func isRunning() -> Bool {
        guard let pid = readPID() else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    func stop() throws {
        let sessionState = readSessionState()
        let pid = sessionState.map(\.pid) ?? readPID()
        let protectedHost = sessionState?.protectedHost ?? readProtectedHost()
        do {
            try helperClient.stop(paths: paths, pid: pid, protectedHost: protectedHost)
        } catch PrivilegedHelperClientError.unavailable(_) where pid == nil && protectedHost == nil {
            return
        } catch PrivilegedHelperClientError.unavailable(_) {
            do {
                guard let runtimeURL = runtimeURL() else {
                    throw XrayRuntimeManager.RuntimeError.binaryNotFound
                }
                try helperInstaller.ensureInstalled(runtimeURL: runtimeURL)
                try helperClient.stop(paths: paths, pid: pid, protectedHost: protectedHost)
            } catch {
                throw XrayTunRuntimeError.stopFailed(summary: readableSummary(from: error), details: diagnosticDetails(from: error))
            }
        } catch {
            throw XrayTunRuntimeError.stopFailed(summary: readableSummary(from: error), details: diagnosticDetails(from: error))
        }
    }

    func teardown() {
        try? stop()
    }

    func capturedLogOutput() -> String? {
        guard let data = try? Data(contentsOf: paths.logFileURL), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func persistSessionState(for session: XrayTunLaunchSession) throws {
        guard let pid = readPID() else { return }
        let state = XrayTunSessionState(
            pid: pid,
            protectedHost: session.protectedHost,
            tunnelInterfaceName: session.tunnelInterfaceName,
            outboundInterface: session.outboundInterface,
            configPath: session.configURL.path,
            startedAt: Date()
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: paths.sessionStateFileURL, options: .atomic)
    }

    private func readSessionState() -> XrayTunSessionState? {
        guard let data = try? Data(contentsOf: paths.sessionStateFileURL) else { return nil }
        return try? JSONDecoder().decode(XrayTunSessionState.self, from: data)
    }

    private func readPID() -> pid_t? {
        guard let rawPID = try? String(contentsOf: paths.pidFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(rawPID),
            pid > 0 else {
            return nil
        }
        return pid
    }

    private func readProtectedHost() -> String? {
        try? String(contentsOf: paths.protectedHostFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readableSummary(from error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription, !description.isEmpty {
            return description.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? description
        }
        return error.localizedDescription
    }

    private func diagnosticDetails(from error: Error) -> String {
        let errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let controlLog = tailControlLog().trimmingCharacters(in: .whitespacesAndNewlines)
        return [errorText, controlLog].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func tailControlLog(maxLines: Int = 40) -> String {
        guard let rawLog = try? String(contentsOf: paths.controlLogFileURL, encoding: .utf8) else { return "" }
        return rawLog
            .split(separator: "\n")
            .suffix(maxLines)
            .joined(separator: "\n")
    }
}

enum XrayTunRuntimeError: LocalizedError {
    case startFailed(summary: String, details: String)
    case stopFailed(summary: String, details: String)

    var errorDescription: String? {
        switch self {
        case let .startFailed(summary, _):
            return summary.isEmpty ? "Failed to start Teleport VPN" : summary
        case let .stopFailed(summary, _):
            return summary.isEmpty ? "Failed to stop Teleport VPN" : summary
        }
    }

    var failureReason: String? {
        switch self {
        case let .startFailed(_, details), let .stopFailed(_, details):
            return details.isEmpty ? nil : details
        }
    }
}
