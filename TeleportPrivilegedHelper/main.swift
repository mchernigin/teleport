import Foundation
import Darwin
import Security

private let helperVersion = "1"
private let helperLabel = "dev.x.teleport.PrivilegedHelper"
private let socketPath = "/var/run/dev.x.teleport.helper.sock"
private let installedXrayPath = "/Library/PrivilegedHelperTools/dev.x.teleport.xray"

struct HelperRequest: Codable {
    var command: String
    var stateDirectoryPath: String?
    var configPath: String?
    var protectedHost: String?
    var tunnelInterfaceName: String?
    var pid: Int32?
}

struct HelperResponse: Codable {
    var success: Bool
    var version: String?
    var summary: String?
    var details: String?
}

final class HelperServer {
    func run() throws {
        let serverFD = try makeListeningSocket()
        defer {
            close(serverFD)
            unlink(socketPath)
        }

        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            handleClient(clientFD)
        }
    }

    private func makeListeningSocket() throws -> Int32 {
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw HelperError("Socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for index in buffer.indices {
                buffer[index] = 0
            }
            for (index, byte) in pathBytes.enumerated() {
                buffer[index] = byte
            }
        }

        let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count + 1)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, length)
            }
        }
        guard bindResult == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }

        let consoleOwner = consoleUserIDs()
        chown(socketPath, consoleOwner.uid, consoleOwner.gid)
        chmod(socketPath, 0o666)

        guard listen(fd, 8) == 0 else {
            let code = errno
            close(fd)
            throw POSIXError(.init(rawValue: code) ?? .EIO)
        }
        return fd
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        do {
            try authorizePeer(fd)
            let requestData = try readAll(from: fd)
            let request = try JSONDecoder().decode(HelperRequest.self, from: requestData)
            let response = handle(request)
            try write(response, to: fd)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let response = HelperResponse(success: false, version: helperVersion, summary: message, details: nil)
            try? write(response, to: fd)
        }
    }

    private func authorizePeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else {
            throw HelperError("Could not verify Teleport client identity")
        }
        let consoleOwner = consoleUserIDs()
        guard uid == consoleOwner.uid else {
            throw HelperError("Rejected request from uid \(uid); expected console uid \(consoleOwner.uid)")
        }
        _ = gid
        try authorizePeerCodeSignature(fd)
    }

    private func authorizePeerCodeSignature(_ fd: Int32) throws {
        var peerPID: pid_t = 0
        var peerPIDLength = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peerPID, &peerPIDLength) == 0 else {
            throw HelperError("Could not identify Teleport client process")
        }

        var secCode: SecCode?
        let attributes = [kSecGuestAttributePid as String: peerPID] as CFDictionary
        var status = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &secCode)
        guard status == errSecSuccess, let secCode else {
            throw HelperError("Could not inspect Teleport client signature: OSStatus \(status)")
        }

        var requirement: SecRequirement?
        let requirementText = "identifier \"dev.x.teleport\" and anchor apple generic and certificate leaf[subject.OU] = \"ZTB359LSTB\""
        status = SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &requirement)
        guard status == errSecSuccess, let requirement else {
            throw HelperError("Could not create Teleport signature requirement: OSStatus \(status)")
        }

        status = SecCodeCheckValidity(secCode, SecCSFlags(), requirement)
        guard status == errSecSuccess else {
            throw HelperError("Rejected request from unsigned or untrusted Teleport client: OSStatus \(status)")
        }
    }

    private func handle(_ request: HelperRequest) -> HelperResponse {
        do {
            switch request.command {
            case "status":
                return HelperResponse(success: true, version: helperVersion, summary: nil, details: nil)
            case "start":
                try XrayTunController().start(request: request)
                return HelperResponse(success: true, version: helperVersion, summary: nil, details: nil)
            case "stop":
                try XrayTunController().stop(request: request)
                return HelperResponse(success: true, version: helperVersion, summary: nil, details: nil)
            default:
                return HelperResponse(success: false, version: helperVersion, summary: "Unsupported helper command: \(request.command)", details: nil)
            }
        } catch {
            let summary = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return HelperResponse(success: false, version: helperVersion, summary: summary, details: nil)
        }
    }

    private func readAll(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        return data
    }

    private func write(_ response: HelperResponse, to fd: Int32) throws {
        let data = try JSONEncoder().encode(response)
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(fd, base.advanced(by: offset), data.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
            }
        }
    }
}

final class XrayTunController {
    func start(request: HelperRequest) throws {
        let stateDirectoryPath = try required(request.stateDirectoryPath, "stateDirectoryPath")
        let configPath = try required(request.configPath, "configPath")
        let protectedHost = try required(request.protectedHost, "protectedHost")
        let tunnelInterfaceName = try required(request.tunnelInterfaceName, "tunnelInterfaceName")

        guard FileManager.default.isExecutableFile(atPath: installedXrayPath) else {
            throw HelperError("Installed Xray runtime is missing. Reinstall Teleport's privileged helper.")
        }

        try runShell(makeStartScript(
            stateDirectoryPath: stateDirectoryPath,
            configPath: configPath,
            protectedHost: protectedHost,
            tunnelInterfaceName: tunnelInterfaceName
        ))
    }

    func stop(request: HelperRequest) throws {
        let stateDirectoryPath = try required(request.stateDirectoryPath, "stateDirectoryPath")
        try runShell(makeStopScript(
            stateDirectoryPath: stateDirectoryPath,
            pid: request.pid,
            protectedHost: request.protectedHost
        ))
    }

    private func required(_ value: String?, _ name: String) throws -> String {
        guard let value, !value.isEmpty else { throw HelperError("Missing \(name)") }
        return value
    }

    private func runShell(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw HelperError([stderr, stdout].filter { !$0.isEmpty }.joined(separator: "\n"))
        }
    }

    private func makeStartScript(stateDirectoryPath: String, configPath: String, protectedHost: String, tunnelInterfaceName: String) -> String {
        let q = shellQuote
        let pidFile = stateDirectoryPath + "/xray-tun.pid"
        let logFile = stateDirectoryPath + "/xray-tun.log"
        let protectedHostFile = stateDirectoryPath + "/xray-tun-protected-host"
        let controlLogFile = stateDirectoryPath + "/xray-tun-control.log"

        return """
        set -eu
        STATE_DIR=\(q(stateDirectoryPath))
        PID_FILE=\(q(pidFile))
        LOG_FILE=\(q(logFile))
        PROTECTED_HOST_FILE=\(q(protectedHostFile))
        CONTROL_LOG_FILE=\(q(controlLogFile))
        XRAY=\(q(installedXrayPath))
        CONFIG=\(q(configPath))
        PROTECTED_HOST=\(q(protectedHost))
        TUN_INTERFACE_NAME=\(q(tunnelInterfaceName))

        \(deleteHostRouteFunction())

        mkdir -p "$STATE_DIR"
        printf '%s helper start requested for %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PROTECTED_HOST" >> "$CONTROL_LOG_FILE"

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
                delete_host_route "$old_protected_host"
            fi
        fi

        route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
        route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true

        rm -f "$PID_FILE"
        : > "$LOG_FILE"
        printf '%s\n' "$PROTECTED_HOST" > "$PROTECTED_HOST_FILE"

        delete_host_route "$PROTECTED_HOST"
        gateway=$(route -n get "$PROTECTED_HOST" 2>/dev/null | awk '/gateway:/{print $2; exit}')
        \(protectHostRouteCommands())

        cd "$STATE_DIR"
        (
            trap '' HUP
            exec "$XRAY" run -c "$CONFIG"
        ) </dev/null >> "$LOG_FILE" 2>&1 &
        pid=$!
        printf '%s\n' "$pid" > "$PID_FILE"
        printf '%s helper launched pid %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"

        sleep 2
        \(protectHostRouteCommands())

        if ! kill -0 "$pid" >/dev/null 2>&1; then
            printf '%s pid %s exited during readiness wait\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"
            delete_host_route "$PROTECTED_HOST"
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
            reason="Teleport VPN started Xray, but macOS did not create the expected TUN interface $TUN_INTERFACE_NAME."
            printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$reason" >> "$CONTROL_LOG_FILE"
            ifconfig >> "$CONTROL_LOG_FILE" 2>&1 || true
            printf '%s\n' "$reason" >&2
            kill "$pid" 2>/dev/null || true
            sleep 0.5
            kill -9 "$pid" 2>/dev/null || true
            delete_host_route "$PROTECTED_HOST"
            rm -f "$PID_FILE"
            exit 1
        fi

        route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
        route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
        route add -net 0.0.0.0/1 -interface "$tun_interface" >> "$CONTROL_LOG_FILE" 2>&1 || true
        route add -net 128.0.0.0/1 -interface "$tun_interface" >> "$CONTROL_LOG_FILE" 2>&1 || true

        \(protectHostRouteCommands())

        public_interface=$(route -n get 1.1.1.1 2>/dev/null | awk '/interface:/{print $2; exit}' || true)
        protected_interface=$(route -n get "$PROTECTED_HOST" 2>/dev/null | awk '/interface:/{print $2; exit}' || true)
        printf '%s pid %s running, tun %s, public route %s, protected route %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" "$tun_interface" "${public_interface:-unknown}" "${protected_interface:-unknown}" >> "$CONTROL_LOG_FILE"

        case "$public_interface" in
            utun*) ;;
            *)
                reason="Teleport VPN started Xray, but macOS did not route public traffic through Teleport's TUN. Disconnect other VPN apps and try again."
                printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$reason" >> "$CONTROL_LOG_FILE"
                netstat -rn -f inet >> "$CONTROL_LOG_FILE" 2>&1 || true
                printf '%s\n' "$reason" >&2
                kill "$pid" 2>/dev/null || true
                sleep 0.5
                kill -9 "$pid" 2>/dev/null || true
                route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
                route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
                delete_host_route "$PROTECTED_HOST"
                rm -f "$PID_FILE"
                exit 1
                ;;
        esac

        case "$protected_interface" in
            utun*)
                reason="Teleport VPN could not keep the proxy server route outside the tunnel. Disconnect other VPN apps and try again, or use System Proxy mode."
                printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$reason" >> "$CONTROL_LOG_FILE"
                printf '%s\n' "$reason" >&2
                kill "$pid" 2>/dev/null || true
                sleep 0.5
                kill -9 "$pid" 2>/dev/null || true
                route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
                route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
                delete_host_route "$PROTECTED_HOST"
                rm -f "$PID_FILE"
                exit 1
                ;;
        esac

        printf '%s pid %s ready\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"
        exit 0
        """
    }

    private func makeStopScript(stateDirectoryPath: String, pid: Int32?, protectedHost: String?) -> String {
        let q = shellQuote
        let pidFile = stateDirectoryPath + "/xray-tun.pid"
        let protectedHostFile = stateDirectoryPath + "/xray-tun-protected-host"
        let controlLogFile = stateDirectoryPath + "/xray-tun-control.log"
        let sessionStateFile = stateDirectoryPath + "/xray-tun-session.json"

        var commands: [String] = []
        commands.append(deleteHostRouteFunction())
        commands.append("mkdir -p \(q(stateDirectoryPath))")
        commands.append("printf '%s helper stop requested\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" >> \(q(controlLogFile))")
        if let pid {
            commands.append(killCommands(pid: pid))
        } else {
            commands.append("if [ -f \(q(pidFile)) ]; then pid=$(cat \(q(pidFile)) 2>/dev/null || true); if [ -n \"$pid\" ]; then kill \"$pid\" 2>/dev/null || true; for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 \"$pid\" 2>/dev/null || break; sleep 0.2; done; kill -0 \"$pid\" 2>/dev/null && kill -9 \"$pid\" 2>/dev/null || true; fi; fi")
        }
        if let protectedHost, !protectedHost.isEmpty {
            commands.append("delete_host_route \(q(protectedHost))")
        } else {
            commands.append("if [ -f \(q(protectedHostFile)) ]; then protected_host=$(cat \(q(protectedHostFile)) 2>/dev/null || true); if [ -n \"$protected_host\" ]; then delete_host_route \"$protected_host\"; fi; fi")
        }
        commands.append("route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true")
        commands.append("route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true")
        commands.append("rm -f \(q(pidFile))")
        commands.append("rm -f \(q(protectedHostFile))")
        commands.append("rm -f \(q(sessionStateFile))")
        return commands.joined(separator: "; ")
    }

    private func killCommands(pid: Int32) -> String {
        "kill \(pid) 2>/dev/null || true; for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done; kill -0 \(pid) 2>/dev/null && kill -9 \(pid) 2>/dev/null || true"
    }

    private func deleteHostRouteFunction() -> String {
        """
        delete_host_route() {
            host="$1"
            i=0
            while route delete -host "$host" >/dev/null 2>&1; do
                i=$((i + 1))
                [ "$i" -ge 10 ] && break
            done
        }
        """
    }

    private func protectHostRouteCommands() -> String {
        """
        if [ -n "$gateway" ]; then
            delete_host_route "$PROTECTED_HOST"
            route add -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || route change -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || true
        fi
        """
    }
}

private func consoleUserIDs() -> (uid: uid_t, gid: gid_t) {
    var statInfo = stat()
    if stat("/dev/console", &statInfo) == 0 {
        return (statInfo.st_uid, statInfo.st_gid)
    }
    return (0, 0)
}

private func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

signal(SIGPIPE, SIG_IGN)
do {
    try HelperServer().run()
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    fputs("\(helperLabel): \(message)\n", stderr)
    exit(1)
}

struct HelperError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message.isEmpty ? "Privileged helper command failed" : message
    }

    var errorDescription: String? { message }
}
