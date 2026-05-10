import AppKit
import Foundation
import SwiftUI

struct AboutSettingsView: View {
    @State private var xrayVersion = "Checking…"

    private let sourceCodeURL = URL(string: "https://codeberg.org/chernigin/teleport")!
    private let issuesURL = URL(string: "https://codeberg.org/chernigin/teleport/issues")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Teleport")
                    .font(.largeTitle.weight(.semibold))
                Text("A tiny macOS Xray menu bar client.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                aboutRow("App version", appVersion)
                aboutRow("Xray version", xrayVersion)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                Button("Source code") {
                    NSWorkspace.shared.open(sourceCodeURL)
                }

                Button("Report a Bug") {
                    NSWorkspace.shared.open(issuesURL)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshXrayVersion()
        }
    }

    private var appVersion: String {
        let dictionary = Bundle.main.infoDictionary
        return dictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }

    private func aboutRow(_ title: String, _ value: String) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 0) {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text(value)
                    .textSelection(.enabled)
            }
        }
    }

    private func refreshXrayVersion() {
        xrayVersion = "Checking…"
        Task {
            xrayVersion = await Self.detectXrayVersion()
        }
    }

    private static func detectXrayVersion() async -> String {
        await Task.detached(priority: .utility) {
            readXrayVersion()
        }.value
    }

    private nonisolated static func readXrayVersion() -> String {
        guard let xrayURL = Bundle.main.url(forResource: "xray", withExtension: nil) else {
            return "Bundled xray not found"
        }

        return runXrayVersionCommand(xrayURL, arguments: ["version"])
            ?? runXrayVersionCommand(xrayURL, arguments: ["--version"])
            ?? "Unavailable"
    }

    private nonisolated static func runXrayVersionCommand(_ xrayURL: URL, arguments: [String]) -> String? {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = xrayURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            return "Timed out"
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let firstLine = output.split(separator: "\n").first {
            return String(firstLine)
        }

        if process.terminationStatus != 0 {
            return "Unavailable (xray exited with status \(process.terminationStatus))"
        }

        return nil
    }
}
