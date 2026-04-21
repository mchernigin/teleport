import AppKit
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
        .frame(width: 360)
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
                Menu {
                    if !viewModel.manualConnections.isEmpty {
                        Section("Saved connections") {
                            ForEach(viewModel.manualConnections) { connection in
                                connectionSelectionButton(connection)
                            }
                        }
                    }

                    if !viewModel.subscriptionSources.isEmpty {
                        Section("Subscriptions") {
                            ForEach(viewModel.subscriptionSources) { source in
                                subscriptionMenu(source)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.selectedConnection?.configuration.displayName ?? "Select connection")
                                .foregroundStyle(.primary)
                            Text(connectionSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .menuStyle(.borderlessButton)
                .disabled(!viewModel.canChangeSelection)
            }
        }
    }

    private var connectionSubtitle: String {
        guard let selectedConnection = viewModel.selectedConnection else {
            return "Choose a connection"
        }

        if let source = viewModel.subscriptionSource(for: selectedConnection) {
            return "From \(source.displayName)"
        }

        return "Manual connection"
    }

    @ViewBuilder
    private func subscriptionMenu(_ source: SubscriptionSource) -> some View {
        let connections = viewModel.importedConnections(for: source.id)
        Menu("\(source.displayName) (\(connections.count))") {
            if connections.isEmpty {
                Button("No imported configs") {}
                    .disabled(true)
            } else {
                ForEach(connections) { connection in
                    connectionSelectionButton(connection)
                }
            }
        }
    }

    @ViewBuilder
    private func connectionSelectionButton(_ connection: SavedConnection) -> some View {
        Button {
            viewModel.selectConnection(id: connection.id)
        } label: {
            let isSelected = connection.id == viewModel.selectedConnectionID
            let prefix = isSelected ? "✓ " : ""
            Text(prefix + connection.configuration.displayName)
        }
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
