import Foundation

final class PrivilegedXrayRuntimeManager: @unchecked Sendable {
    private let bundle: Bundle
    private let fileManager: FileManager
    private let stateDirectoryURL: URL
    private let pidFileURL: URL
    private let logFileURL: URL
    private let launchScriptURL: URL
    private let protectedHostFileURL: URL
    private let controlLogFileURL: URL

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        stateDirectoryURL = baseURL.appendingPathComponent("teleport", isDirectory: true)
        pidFileURL = stateDirectoryURL.appendingPathComponent("xray-tun.pid")
        logFileURL = stateDirectoryURL.appendingPathComponent("xray-tun.log")
        launchScriptURL = stateDirectoryURL.appendingPathComponent("launch-xray-tun.sh")
        protectedHostFileURL = stateDirectoryURL.appendingPathComponent("xray-tun-protected-host")
        controlLogFileURL = stateDirectoryURL.appendingPathComponent("xray-tun-control.log")
    }

    func runtimeURL() -> URL? {
        bundle.url(forResource: "xray", withExtension: nil)
    }

    func start(configURL: URL, protectedHost: String, tunnelInterfaceName: String) throws {
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)

        guard let runtimeURL = runtimeURL() else {
            throw XrayRuntimeManager.RuntimeError.binaryNotFound
        }

        let launchScript = makeLaunchScript(
            runtimeURL: runtimeURL,
            configURL: configURL,
            protectedHost: protectedHost,
            tunnelInterfaceName: tunnelInterfaceName
        )
        try launchScript.write(to: launchScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: launchScriptURL.path)

        try runAdministratorShellScript(shellQuote(launchScriptURL.path))
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
        let pid = readPID()
        let protectedHost = readProtectedHost()
        let stopScript = makeStopScript(pid: pid, protectedHost: protectedHost)
        try runAdministratorShellScript(stopScript)
    }

    func teardown() {
        try? stop()
    }

    func capturedLogOutput() -> String? {
        guard let data = try? Data(contentsOf: logFileURL), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func makeLaunchScript(runtimeURL: URL, configURL: URL, protectedHost: String, tunnelInterfaceName: String) -> String {
        """
        #!/bin/sh
        set -eu

        STATE_DIR=\(shellQuote(stateDirectoryURL.path))
        PID_FILE=\(shellQuote(pidFileURL.path))
        LOG_FILE=\(shellQuote(logFileURL.path))
        PROTECTED_HOST_FILE=\(shellQuote(protectedHostFileURL.path))
        CONTROL_LOG_FILE=\(shellQuote(controlLogFileURL.path))
        XRAY=\(shellQuote(runtimeURL.path))
        CONFIG=\(shellQuote(configURL.path))
        PROTECTED_HOST=\(shellQuote(protectedHost))
        TUN_INTERFACE_NAME=\(shellQuote(tunnelInterfaceName))

        mkdir -p "$STATE_DIR"
        printf '%s start requested for %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PROTECTED_HOST" >> "$CONTROL_LOG_FILE"

        if [ -f "$PID_FILE" ]; then
            old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
            if [ -n "$old_pid" ]; then
                kill "$old_pid" 2>/dev/null || true
                sleep 0.5
                kill -9 "$old_pid" 2>/dev/null || true
            fi
        fi

        if [ -f "$PROTECTED_HOST_FILE" ]; then
            old_protected_host=$(cat "$PROTECTED_HOST_FILE" 2>/dev/null || true)
            if [ -n "$old_protected_host" ]; then
                route delete -host "$old_protected_host" >/dev/null 2>&1 || true
            fi
        fi

        route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
        route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true

        rm -f "$PID_FILE"
        : > "$LOG_FILE"
        printf '%s\n' "$PROTECTED_HOST" > "$PROTECTED_HOST_FILE"

        gateway=$(route -n get "$PROTECTED_HOST" 2>/dev/null | awk '/gateway:/{print $2; exit}')
        outbound_interface=$(route -n get "$PROTECTED_HOST" 2>/dev/null | awk '/interface:/{print $2; exit}')
        if [ -n "$gateway" ]; then
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route add -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || route change -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || true
        fi

        cd "$STATE_DIR"
        (
            trap '' HUP
            exec "$XRAY" run -c "$CONFIG"
        ) </dev/null >> "$LOG_FILE" 2>&1 &
        pid=$!
        printf '%s\n' "$pid" > "$PID_FILE"
        printf '%s launched pid %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"

        sleep 2
        if [ -n "$gateway" ]; then
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route add -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || route change -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || true
        fi

        if ! kill -0 "$pid" >/dev/null 2>&1; then
            printf '%s pid %s exited during readiness wait\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"
            rm -f "$PID_FILE"
            cat "$LOG_FILE" >&2 || true
            exit 1
        fi

        tun_interface=""
        if ifconfig "$TUN_INTERFACE_NAME" >/dev/null 2>&1; then
            tun_interface="$TUN_INTERFACE_NAME"
        fi
        if [ -z "$tun_interface" ]; then
            tun_interface=$(ifconfig | awk '
                /^utun[0-9]+:/ { iface=$1; sub(":", "", iface); next }
                /inet 169\\.254\\./ { print iface; exit }
                /inet 172\\.18\\.0\\.1/ { print iface; exit }
                /inet 198\\.18\\./ { print iface; exit }
            ')
        fi
        if [ -z "$tun_interface" ]; then
            printf '%s no Xray TUN interface was found for requested name %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$TUN_INTERFACE_NAME" >> "$CONTROL_LOG_FILE"
            ifconfig >> "$CONTROL_LOG_FILE" 2>&1 || true
            kill "$pid" 2>/dev/null || true
            sleep 0.5
            kill -9 "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
            exit 1
        fi

        route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
        route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
        route add -net 0.0.0.0/1 -interface "$tun_interface" >> "$CONTROL_LOG_FILE" 2>&1 || true
        route add -net 128.0.0.0/1 -interface "$tun_interface" >> "$CONTROL_LOG_FILE" 2>&1 || true

        if [ -n "$gateway" ]; then
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route add -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || route change -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || true
        fi

        public_interface=$(route -n get 1.1.1.1 2>/dev/null | awk '/interface:/{print $2; exit}' || true)
        protected_interface=$(route -n get "$PROTECTED_HOST" 2>/dev/null | awk '/interface:/{print $2; exit}' || true)
        printf '%s pid %s running, tun %s, public route %s, protected route %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" "$tun_interface" "${public_interface:-unknown}" "${protected_interface:-unknown}" >> "$CONTROL_LOG_FILE"

        case "$public_interface" in
            utun*) ;;
            *)
                printf '%s public traffic did not select TUN after manual route setup\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONTROL_LOG_FILE"
                netstat -rn -f inet >> "$CONTROL_LOG_FILE" 2>&1 || true
                kill "$pid" 2>/dev/null || true
                sleep 0.5
                kill -9 "$pid" 2>/dev/null || true
                route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
                route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
                rm -f "$PID_FILE"
                exit 1
                ;;
        esac

        case "$protected_interface" in
            utun*)
                printf '%s protected host still selected TUN; refusing to start to avoid a routing loop\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONTROL_LOG_FILE"
                kill "$pid" 2>/dev/null || true
                sleep 0.5
                kill -9 "$pid" 2>/dev/null || true
                route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
                route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
                rm -f "$PID_FILE"
                exit 1
                ;;
        esac

        printf '%s pid %s ready\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"
        exit 0
        """
    }

    private func makeStopScript(pid: pid_t?, protectedHost: String?) -> String {
        var commands: [String] = []

        commands.append("mkdir -p \(shellQuote(stateDirectoryURL.path))")
        commands.append("printf '%s stop requested\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" >> \(shellQuote(controlLogFileURL.path))")

        if let pid {
            commands.append("kill \(pid) 2>/dev/null || true")
            commands.append("for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done")
            commands.append("kill -0 \(pid) 2>/dev/null && kill -9 \(pid) 2>/dev/null || true")
        }

        if let protectedHost, !protectedHost.isEmpty {
            commands.append("route delete -host \(shellQuote(protectedHost)) >/dev/null 2>&1 || true")
        }

        commands.append("route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true")
        commands.append("route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true")
        commands.append("rm -f \(shellQuote(pidFileURL.path))")
        commands.append("rm -f \(shellQuote(protectedHostFileURL.path))")
        return commands.joined(separator: "; ")
    }

    private func readPID() -> pid_t? {
        guard let rawPID = try? String(contentsOf: pidFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(rawPID),
            pid > 0 else {
            return nil
        }
        return pid
    }

    private func readProtectedHost() -> String? {
        try? String(contentsOf: protectedHostFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runAdministratorShellScript(_ shellScript: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "do shell script \"\(appleScriptQuote(shellScript))\" with administrator privileges"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let controlLog = tailControlLog().trimmingCharacters(in: .whitespacesAndNewlines)
            let message = [stderr, controlLog].filter { !$0.isEmpty }.joined(separator: "\n")
            throw PrivilegedRuntimeError.commandFailed(message)
        }
    }

    private func tailControlLog(maxLines: Int = 20) -> String {
        guard let rawLog = try? String(contentsOf: controlLogFileURL, encoding: .utf8) else { return "" }
        return rawLog
            .split(separator: "\n")
            .suffix(maxLines)
            .joined(separator: "\n")
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    enum PrivilegedRuntimeError: LocalizedError {
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case let .commandFailed(message):
                return message.isEmpty ? "Failed to run Xray with administrator privileges" : message
            }
        }
    }
}
