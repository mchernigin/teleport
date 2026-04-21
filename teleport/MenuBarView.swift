import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            configurationSection
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
        HStack(alignment: .top) {
            Text("Teleport")
                .font(.headline)

            Spacer()

            Text(headerStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(headerStatusColor)
        }
    }

    private var headerStatusText: String {
        if viewModel.isConnected {
            return "Connected"
        }

        switch viewModel.connectionPhase {
        case .starting:
            return "Connecting"
        case .stopping:
            return "Disconnecting"
        case .failed:
            return "Error"
        case .unconfigured:
            return "No config"
        case .ready, .stopped, .running:
            return "Disconnected"
        }
    }

    private var headerStatusColor: Color {
        switch viewModel.connectionPhase {
        case .failed:
            return .red
        case .starting, .stopping:
            return .orange
        case .running where viewModel.proxyPhase == .enabled:
            return Color(NSColor.systemGreen.withAlphaComponent(0.72))
        case .unconfigured:
            return .secondary
        default:
            return .secondary
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection")
                .font(.subheadline.weight(.semibold))

            if viewModel.savedConnections.isEmpty {
                Text("No saved connections")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Open Settings") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
            } else {
                Picker("Selected connection", selection: selectedConnectionBinding) {
                    ForEach(viewModel.savedConnections) { connection in
                        Text(connection.configuration.displayName)
                            .tag(Optional(connection.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!viewModel.canChangeSelection)
            }
        }
    }

    private var selectedConnectionBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.selectedConnectionID },
            set: { newValue in
                if let newValue {
                    viewModel.selectConnection(id: newValue)
                }
            }
        )
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))

            HStack {
                Button(viewModel.isConnected ? "Disconnect" : "Connect") {
                    if viewModel.isConnected || viewModel.canDisconnect {
                        viewModel.disconnect()
                    } else {
                        viewModel.connect()
                    }
                }
                .disabled(!viewModel.canConnect && !viewModel.canDisconnect)

                Button("Settings") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}

#Preview {
    MenuBarView(viewModel: AppViewModel())
}
