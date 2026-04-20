import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            configurationSection
            statusSection
            actionSection

            if let error = viewModel.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Teleport")
                .font(.headline)
            Text(viewModel.statusSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VLESS link")
                .font(.subheadline.weight(.semibold))

            TextField("vless://…", text: $viewModel.draftLink)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())

            HStack {
                Button("Paste") {
                    viewModel.pasteFromClipboard()
                }

                Button("Save link") {
                    viewModel.saveLink()
                }
                .keyboardShortcut(.return)
            }

            if let configuration = viewModel.savedConfiguration {
                Label(configuration.displayName, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No saved configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.subheadline.weight(.semibold))
            statusRow(title: "Connection", value: viewModel.connectionPhase.rawValue.capitalized)
            statusRow(title: "Proxy", value: viewModel.proxyPhase.rawValue.capitalized)
            statusRow(title: "HTTP", value: "\(viewModel.proxyEndpoint.host):\(viewModel.proxyEndpoint.httpPort)")
            statusRow(title: "SOCKS", value: "\(viewModel.proxyEndpoint.host):\(viewModel.proxyEndpoint.socksPort)")
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))

            HStack {
                Button(viewModel.canStop ? "Stop Xray" : "Start Xray") {
                    if viewModel.canStop {
                        viewModel.stopConnection()
                    } else {
                        viewModel.startConnection()
                    }
                }
                .disabled(!viewModel.canStart && !viewModel.canStop)

                Button(viewModel.proxyPhase == .enabled ? "Disable proxy" : "Enable proxy") {
                    if viewModel.proxyPhase == .enabled {
                        viewModel.disableProxy()
                    } else {
                        viewModel.enableProxy()
                    }
                }
                .disabled((viewModel.proxyPhase == .enabled) ? false : !viewModel.canEnableProxy)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

#Preview {
    MenuBarView(viewModel: AppViewModel())
}
