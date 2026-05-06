import Foundation

struct XrayTunLaunchScriptBuilder: Sendable {
    var paths: XrayTunRuntimePaths

    func makeStartScript(runtimeURL: URL, session: XrayTunLaunchSession) -> String {
        let q = PrivilegedShellRunner.shellQuote
        return """
        #!/bin/sh
        set -eu

        STATE_DIR=\(q(paths.stateDirectoryURL.path))
        PID_FILE=\(q(paths.pidFileURL.path))
        LOG_FILE=\(q(paths.logFileURL.path))
        PROTECTED_HOST_FILE=\(q(paths.protectedHostFileURL.path))
        CONTROL_LOG_FILE=\(q(paths.controlLogFileURL.path))
        XRAY=\(q(runtimeURL.path))
        CONFIG=\(q(session.configURL.path))
        PROTECTED_HOST=\(q(session.protectedHost))
        TUN_INTERFACE_NAME=\(q(session.tunnelInterfaceName))

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
        \(protectHostRouteCommands())

        cd "$STATE_DIR"
        (
            trap '' HUP
            exec "$XRAY" run -c "$CONFIG"
        ) </dev/null >> "$LOG_FILE" 2>&1 &
        pid=$!
        printf '%s\n' "$pid" > "$PID_FILE"
        printf '%s launched pid %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" >> "$CONTROL_LOG_FILE"

        sleep 2
        \(protectHostRouteCommands())

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

        \(protectHostRouteCommands())

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

    func makeStopScript(pid: pid_t?, protectedHost: String?) -> String {
        let q = PrivilegedShellRunner.shellQuote
        var commands: [String] = []
        commands.append("mkdir -p \(q(paths.stateDirectoryURL.path))")
        commands.append("printf '%s stop requested\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" >> \(q(paths.controlLogFileURL.path))")

        if let pid {
            commands.append("kill \(pid) 2>/dev/null || true")
            commands.append("for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 \(pid) 2>/dev/null || break; sleep 0.2; done")
            commands.append("kill -0 \(pid) 2>/dev/null && kill -9 \(pid) 2>/dev/null || true")
        }

        if let protectedHost, !protectedHost.isEmpty {
            commands.append("route delete -host \(q(protectedHost)) >/dev/null 2>&1 || true")
        }

        commands.append("route delete -net 0.0.0.0/1 >/dev/null 2>&1 || true")
        commands.append("route delete -net 128.0.0.0/1 >/dev/null 2>&1 || true")
        commands.append("rm -f \(q(paths.pidFileURL.path))")
        commands.append("rm -f \(q(paths.protectedHostFileURL.path))")
        commands.append("rm -f \(q(paths.sessionStateFileURL.path))")
        return commands.joined(separator: "; ")
    }

    private func protectHostRouteCommands() -> String {
        """
        if [ -n "$gateway" ]; then
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route delete -host "$PROTECTED_HOST" >/dev/null 2>&1 || true
            route add -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || route change -host "$PROTECTED_HOST" "$gateway" >> "$CONTROL_LOG_FILE" 2>&1 || true
        fi
        """
    }
}
