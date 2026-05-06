import Foundation

struct ConnectionBackendFactory {
    func makeBackend(for mode: ConnectionMode) -> ConnectionBackend {
        switch mode {
        case .systemProxy:
            return SystemProxyConnectionBackend(
                runtimeManager: XrayRuntimeManager(),
                proxyService: SystemProxyService()
            )
        case .vpn:
            return XrayTunConnectionBackend(runtimeManager: PrivilegedXrayRuntimeManager())
        }
    }
}

final class XrayTunConnectionBackend: ConnectionBackend {
    private let runtimeManager: PrivilegedXrayRuntimeManager

    init(runtimeManager: PrivilegedXrayRuntimeManager) {
        self.runtimeManager = runtimeManager
    }

    func hasRestorableState() -> Bool { false }

    func restorePreviousState() throws {}

    func start(configuration: ConnectionConfiguration, endpoint: ProxyEndpoint) throws {
        _ = endpoint
        if let existingVPNInterface = Self.existingVPNDefaultRouteInterface() {
            throw XrayTunConnectionError.existingVPNDetected(existingVPNInterface)
        }

        let outboundInterface = Self.outboundInterface(for: configuration.host) ?? "auto"
        let tunnelInterfaceName = Self.randomTunnelInterfaceName()
        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeTunnelConfig(
            for: configuration,
            interfaceName: tunnelInterfaceName,
            outboundInterface: outboundInterface
        )
        try runtimeManager.start(
            configURL: configURL,
            protectedHost: configuration.host,
            tunnelInterfaceName: tunnelInterfaceName
        )
        guard runtimeManager.waitUntilRunning() else {
            let detail = runtimeManager.capturedLogOutput()?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw XrayRuntimeManager.RuntimeError.startupTimedOut(detail)
        }
    }

    func reconnect(configuration: ConnectionConfiguration, endpoint: ProxyEndpoint, shouldDisableExistingProxy: Bool) throws {
        _ = shouldDisableExistingProxy
        try stop(shouldDisableProxy: false)
        try start(configuration: configuration, endpoint: endpoint)
    }

    func stop(shouldDisableProxy: Bool) throws {
        _ = shouldDisableProxy
        try runtimeManager.stop()
    }

    func teardown() {
        runtimeManager.teardown()
    }

    private static func outboundInterface(for host: String) -> String? {
        routeInterface(for: host)
    }

    private static func randomTunnelInterfaceName() -> String {
        "utun\(Int.random(in: 10 ... 99))"
    }

    private static func routeInterface(for host: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", host]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("interface:") }?
            .split(separator: " ")
            .last
            .map(String.init)
    }

    private static func hasXrayTunnelInterface() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0 else { return false }
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let interfaceBlocks = output.components(separatedBy: "\nutun")
        return interfaceBlocks.contains { block in
            block.contains("inet 198.18.") || block.contains("inet 172.18.")
        }
    }

    private static func existingVPNDefaultRouteInterface() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        process.arguments = ["-rn", "-f", "inet"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output
            .split(separator: "\n")
            .map { $0.split(separator: " ").map(String.init) }
            .first { columns in
                columns.first == "default" && columns.last?.hasPrefix("utun") == true
            }?
            .last
    }
}

enum XrayTunConnectionError: LocalizedError {
    case existingVPNDetected(String)
    case tunnelRouteNotReady

    var errorDescription: String? {
        switch self {
        case let .existingVPNDetected(interface):
            return "Another VPN appears to be active on \(interface). Disconnect it before using Teleport VPN mode, or use System Proxy mode."
        case .tunnelRouteNotReady:
            return "Teleport VPN started Xray, but macOS did not route public traffic through Teleport's TUN. Disconnect other VPN apps and try again."
        }
    }
}
