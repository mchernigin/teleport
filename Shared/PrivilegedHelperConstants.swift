import Foundation

enum PrivilegedHelperConstants {
    static let version = "4"
    static let label = "dev.x.teleport.PrivilegedHelper"
    static let socketPath = "/var/run/dev.x.teleport.helper.sock"
    static let installedToolPath = "/Library/PrivilegedHelperTools/dev.x.teleport.PrivilegedHelper"
    static let installedXrayPath = "/Library/PrivilegedHelperTools/dev.x.teleport.xray"
    static let launchDaemonPlistPath = "/Library/LaunchDaemons/dev.x.teleport.PrivilegedHelper.plist"
}
