import Foundation

struct XrayTunRouteInspector: Sendable {
    func outboundInterface(for host: String) -> String? {
        routeInterface(for: host)
    }

    func existingVPNDefaultRouteInterface() -> String? {
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

    func routeInterface(for host: String) -> String? {
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

    func tunnelInterfaceName() -> String {
        "utun"
    }
}
