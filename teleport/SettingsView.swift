import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TabView {
            ConnectionsSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Connections", systemImage: "link")
                }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct ConnectionsSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add connection")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("vless:// or trojan://…", text: $viewModel.draftLink)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())
                        .onSubmit {
                            viewModel.addConnection()
                        }

                    Button {
                        viewModel.addConnection()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .keyboardShortcut(.return)
                }

                if let error = viewModel.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Saved connections")
                    .font(.headline)

                if viewModel.savedConnections.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        ContentUnavailableView(
                            "No connections",
                            systemImage: "tray",
                            description: Text("Paste a VLESS or Trojan link above to add your first connection.")
                        )
                        .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.savedConnections) { connection in
                            connectionRow(connection)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func connectionRow(_ connection: SavedConnection) -> some View {
        let isSelected = connection.id == viewModel.selectedConnectionID
        let configuration = connection.configuration

        HStack(spacing: 12) {
            Button {
                viewModel.selectConnection(id: connection.id)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.displayName)
                            .foregroundStyle(.primary)
                        Text("\(configuration.protocolType.displayName) • \(configuration.endpointSummary)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canChangeSelection && !isSelected)

            Button(role: .destructive) {
                viewModel.removeConnection(id: connection.id)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(isSelected && !viewModel.canChangeSelection)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView(viewModel: AppViewModel())
}
