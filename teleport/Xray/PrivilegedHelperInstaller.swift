import Foundation

struct PrivilegedHelperInstaller: Sendable {
    private let bundle: Bundle
    private let shellRunner: PrivilegedShellRunner

    init(bundle: Bundle = .main, shellRunner: PrivilegedShellRunner = PrivilegedShellRunner()) {
        self.bundle = bundle
        self.shellRunner = shellRunner
    }

    func ensureInstalled(runtimeURL: URL) throws {
        guard let helperURL = bundledHelperURL() else {
            throw PrivilegedHelperInstallerError.bundledHelperMissing
        }
        if isInstalledAndRunning(helperURL: helperURL, runtimeURL: runtimeURL) {
            return
        }
        try install(helperURL: helperURL, runtimeURL: runtimeURL)
        try waitUntilRunning()
    }

    private func isInstalledAndRunning(helperURL: URL, runtimeURL: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: PrivilegedHelperClient.installedToolPath),
              fileManager.isExecutableFile(atPath: PrivilegedHelperClient.installedXrayPath),
              fileManager.contentsEqual(atPath: helperURL.path, andPath: PrivilegedHelperClient.installedToolPath),
              fileManager.contentsEqual(atPath: runtimeURL.path, andPath: PrivilegedHelperClient.installedXrayPath) else {
            return false
        }
        guard let response = try? PrivilegedHelperClient().status(), response.success else {
            return false
        }
        return response.version == PrivilegedHelperClient.expectedVersion
    }

    private func install(helperURL: URL, runtimeURL: URL) throws {
        let plist = launchDaemonPlist()
        let script = installScript(helperURL: helperURL, runtimeURL: runtimeURL, plist: plist)
        do {
            try shellRunner.runAdministratorShellScript(script, prompt: administratorPrompt)
        } catch {
            throw PrivilegedHelperInstallerError.installFailed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func bundledHelperURL() -> URL? {
        let bundleURL = bundle.bundleURL
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Library/PrivilegedHelperTools/\(PrivilegedHelperClient.label)"),
            bundleURL.appendingPathComponent("Contents/MacOS/\(PrivilegedHelperClient.label)")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func waitUntilRunning() throws {
        let deadline = Date().addingTimeInterval(5)
        var lastError: Error?
        while Date() < deadline {
            do {
                let response = try PrivilegedHelperClient().status()
                if response.success, response.version == PrivilegedHelperClient.expectedVersion {
                    return
                }
            } catch {
                lastError = error
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw PrivilegedHelperInstallerError.helperDidNotStart(
            (lastError as? LocalizedError)?.errorDescription ?? lastError?.localizedDescription
        )
    }

    private var administratorPrompt: String {
        """
        Teleport needs administrator access to install or update its privileged helper for VPN mode.

        The helper lets Teleport start and stop Xray TUN and configure system routing. Your password is only used by macOS to approve this privileged install.
        """
    }

    private func installScript(helperURL: URL, runtimeURL: URL, plist: String) -> String {
        let q = PrivilegedShellRunner.shellQuote
        return """
        set -eu
        HELPER_SRC=\(q(helperURL.path))
        XRAY_SRC=\(q(runtimeURL.path))
        HELPER_DST=\(q(PrivilegedHelperClient.installedToolPath))
        XRAY_DST=\(q(PrivilegedHelperClient.installedXrayPath))
        PLIST_DST=\(q(PrivilegedHelperClient.launchDaemonPlistPath))
        LABEL=\(q(PrivilegedHelperClient.label))

        launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
        rm -f \(q(PrivilegedHelperClient.socketPath))
        mkdir -p /Library/PrivilegedHelperTools
        cp "$HELPER_SRC" "$HELPER_DST"
        cp "$XRAY_SRC" "$XRAY_DST"
        chown root:wheel "$HELPER_DST" "$XRAY_DST"
        chmod 755 "$HELPER_DST" "$XRAY_DST"
        cat > "$PLIST_DST" <<'TELEPORT_HELPER_PLIST'
        \(plist)
        TELEPORT_HELPER_PLIST
        chown root:wheel "$PLIST_DST"
        chmod 644 "$PLIST_DST"
        launchctl bootstrap system "$PLIST_DST"
        launchctl kickstart -k "system/$LABEL" >/dev/null 2>&1 || true
        """
    }

    private func launchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(PrivilegedHelperClient.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(PrivilegedHelperClient.installedToolPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/var/log/teleport-privileged-helper.log</string>
            <key>StandardErrorPath</key>
            <string>/var/log/teleport-privileged-helper.log</string>
        </dict>
        </plist>
        """
    }
}

enum PrivilegedHelperInstallerError: LocalizedError {
    case bundledHelperMissing
    case installFailed(String)
    case helperDidNotStart(String?)

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            return "Teleport's privileged helper is missing from the app bundle. Rebuild or reinstall Teleport."
        case let .installFailed(message):
            return message.isEmpty ? "Failed to install Teleport's privileged helper" : message
        case .helperDidNotStart:
            return "Teleport's privileged helper was installed but did not start."
        }
    }

    var failureReason: String? {
        switch self {
        case let .helperDidNotStart(details):
            return details
        default:
            return nil
        }
    }
}
