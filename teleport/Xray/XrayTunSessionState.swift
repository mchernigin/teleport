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
    var configURL: URL
    var protectedHost: String
    var tunnelInterfaceName: String
    var outboundInterface: String
}

struct XrayTunRuntimePaths: Sendable {
    var stateDirectoryURL: URL
    var pidFileURL: URL
    var logFileURL: URL
    var launchScriptURL: URL
    var protectedHostFileURL: URL
    var controlLogFileURL: URL
    var sessionStateFileURL: URL

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        stateDirectoryURL = baseURL.appendingPathComponent("teleport", isDirectory: true)
        pidFileURL = stateDirectoryURL.appendingPathComponent("xray-tun.pid")
        logFileURL = stateDirectoryURL.appendingPathComponent("xray-tun.log")
        launchScriptURL = stateDirectoryURL.appendingPathComponent("launch-xray-tun.sh")
        protectedHostFileURL = stateDirectoryURL.appendingPathComponent("xray-tun-protected-host")
        controlLogFileURL = stateDirectoryURL.appendingPathComponent("xray-tun-control.log")
        sessionStateFileURL = stateDirectoryURL.appendingPathComponent("xray-tun-session.json")
    }
}
