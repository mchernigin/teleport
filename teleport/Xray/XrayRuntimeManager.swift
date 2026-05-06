import AppKit
import CFNetwork
import Combine
import Darwin
import Foundation
import Network
import SystemConfiguration

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
