import Foundation

struct XrayTunSessionState: Codable, Sendable {
    var pid: Int32
    var protectedHost: String
    var tunnelInterfaceName: String
    var outboundInterface: String
    var configPath: String
    var startedAt: Date
}

struct XrayTunLaunchSession: Sendable {
    var configData: Data
    var protectedHost: String
    var tunnelInterfaceName: String
    var outboundInterface: String
}

struct XrayTunRuntimePaths: Sendable {
    var stateDirectoryURL: URL
    var pidFileURL: URL
    var logFileURL: URL
    var protectedHostFileURL: URL
    var controlLogFileURL: URL
    var sessionStateFileURL: URL
    var configFileURL: URL

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let helperStateDirectoryURL = URL(fileURLWithPath: PrivilegedHelperConstants.helperStateDirectoryPath, isDirectory: true)
        stateDirectoryURL = baseURL.appendingPathComponent("teleport", isDirectory: true)
        pidFileURL = helperStateDirectoryURL.appendingPathComponent("xray-tun.pid")
        logFileURL = helperStateDirectoryURL.appendingPathComponent("xray-tun.log")
        protectedHostFileURL = helperStateDirectoryURL.appendingPathComponent("xray-tun-protected-host")
        controlLogFileURL = helperStateDirectoryURL.appendingPathComponent("xray-tun-control.log")
        sessionStateFileURL = stateDirectoryURL.appendingPathComponent("xray-tun-session.json")
        configFileURL = helperStateDirectoryURL.appendingPathComponent("xray-tun-config.json")
    }
}
