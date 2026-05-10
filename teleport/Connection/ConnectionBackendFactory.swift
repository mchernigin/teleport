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
            return XrayTunConnectionBackend(
                runtimeManager: PrivilegedXrayRuntimeManager(),
                routeInspector: XrayTunRouteInspector(),
                systemProxyService: SystemProxyService()
            )
        }
    }
}

final class XrayTunConnectionBackend: ConnectionBackend {
    private let runtimeManager: PrivilegedXrayRuntimeManager
    private let routeInspector: XrayTunRouteInspector
    private let systemProxyService: SystemProxyService

    init(runtimeManager: PrivilegedXrayRuntimeManager, routeInspector: XrayTunRouteInspector, systemProxyService: SystemProxyService) {
        self.runtimeManager = runtimeManager
        self.routeInspector = routeInspector
        self.systemProxyService = systemProxyService
    }

    func hasRestorableState() -> Bool { false }

    func hasActiveRuntimeSession() -> Bool {
        runtimeManager.isRunning()
    }

    func restorePreviousState() throws {}

    func start(configuration: ConnectionConfiguration, endpoint: ProxyEndpoint) throws {
        _ = endpoint
        if let existingVPNInterface = routeInspector.existingVPNDefaultRouteInterface() {
            throw XrayTunConnectionError.existingVPNDetected(existingVPNInterface)
        }

        try systemProxyService.disableProxy()

        let outboundInterface = routeInspector.outboundInterface(for: configuration.host) ?? "auto"
        let tunnelInterfaceName = routeInspector.nextAvailableTunnelInterfaceName()
        let configURL = try XrayConfigurationWriter(proxyEndpoint: .default).writeTunnelConfig(
            for: configuration,
            interfaceName: tunnelInterfaceName,
            outboundInterface: outboundInterface
        )
        try runtimeManager.start(
            session: XrayTunLaunchSession(
                configURL: configURL,
                protectedHost: configuration.host,
                tunnelInterfaceName: tunnelInterfaceName,
                outboundInterface: outboundInterface
            )
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
}

enum XrayTunConnectionError: LocalizedError {
    case existingVPNDetected(String)

    var errorDescription: String? {
        switch self {
        case let .existingVPNDetected(interface):
            return "Another VPN appears to be active on \(interface). Disconnect it before using Teleport VPN mode, or use System Proxy mode."
        }
    }
}
