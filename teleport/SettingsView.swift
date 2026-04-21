import AppKit
import CoreImage.CIFilterBuiltins
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
        .frame(minWidth: 620, minHeight: 460)
    }
}

private struct ConnectionsSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedSubscriptionIDs: Set<UUID> = []
    @State private var editingSubscription: SubscriptionSource?
    @State private var qrPayload: QRPayload?
    @State private var activeShareMenu: ShareMenuPayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add connection or subscription")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("vless://, trojan://, or https://subscription…", text: $viewModel.draftLink)
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

            if viewModel.savedConnections.isEmpty && viewModel.subscriptionSources.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    ContentUnavailableView(
                        "No connections",
                        systemImage: "tray",
                        description: Text("Paste a VLESS, Trojan, or subscription URL above to add your first connection.")
                    )
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !viewModel.manualConnections.isEmpty {
                        Section("Saved connections") {
                            ForEach(viewModel.manualConnections) { connection in
                                manualConnectionRow(connection)
                            }
                        }
                    }

                    Section("Subscriptions") {
                        if viewModel.subscriptionSources.isEmpty {
                            Text("No subscriptions yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.subscriptionSources) { source in
                                subscriptionSection(source)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(item: $editingSubscription) { source in
            SubscriptionSettingsSheet(
                source: source,
                onSave: { customName, urlString, autoUpdateIntervalMinutes in
                    viewModel.updateSubscriptionSettings(
                        id: source.id,
                        customName: customName,
                        urlString: urlString,
                        autoUpdateIntervalMinutes: autoUpdateIntervalMinutes
                    )
                }
            )
        }
        .sheet(item: $qrPayload) { payload in
            QRCodeSheet(payload: payload)
        }
    }

    @ViewBuilder
    private func manualConnectionRow(_ connection: SavedConnection) -> some View {
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

            shareButton(
                title: connection.configuration.displayName,
                value: connection.configuration.rawLink
            )

            Button(role: .destructive) {
                viewModel.removeConnection(id: connection.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isSelected && !viewModel.canChangeSelection)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func subscriptionSection(_ source: SubscriptionSource) -> some View {
        let isExpanded = expandedSubscriptionIDs.contains(source.id)
        let importedConnections = viewModel.importedConnections(for: source.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    toggleSubscription(source.id)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(source.displayName)
                                    .font(.subheadline.weight(.semibold))

                                if viewModel.isRefreshingSubscription(source.id) {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }

                            Text(subscriptionSummary(for: source))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 12)

                shareButton(
                    title: source.displayName,
                    value: source.urlString
                )

                Button {
                    editingSubscription = source
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.refreshSubscription(id: source.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isRefreshingSubscription(source.id))

                Button(role: .destructive) {
                    expandedSubscriptionIDs.remove(source.id)
                    viewModel.removeSubscription(id: source.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if let error = source.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if isExpanded {
                if importedConnections.isEmpty {
                    Text("No imported configs yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(importedConnections) { connection in
                            importedConnectionRow(connection, source: source)
                        }
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func importedConnectionRow(_ connection: SavedConnection, source: SubscriptionSource) -> some View {
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

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canChangeSelection && !isSelected)

            shareButton(
                title: configuration.displayName,
                value: configuration.rawLink
            )
        }
    }

    @ViewBuilder
    private func shareButton(title: String, value: String) -> some View {
        let payload = ShareMenuPayload(title: title, value: value)
        let isPresented = Binding(
            get: { activeShareMenu == payload },
            set: { newValue in
                activeShareMenu = newValue ? payload : nil
            }
        )

        Button {
            activeShareMenu = activeShareMenu == payload ? nil : payload
        } label: {
            actionIcon("square.and.arrow.up")
        }
        .buttonStyle(.borderless)
        .popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            ShareActionPopover(
                onCopy: {
                    copyToClipboard(value)
                    activeShareMenu = nil
                },
                onShowQR: {
                    qrPayload = QRPayload(title: title, value: value)
                    activeShareMenu = nil
                }
            )
        }
    }

    @ViewBuilder
    private func actionIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 18, height: 18, alignment: .center)
            .contentShape(Rectangle())
    }

    private func toggleSubscription(_ id: UUID) {
        if expandedSubscriptionIDs.contains(id) {
            expandedSubscriptionIDs.remove(id)
        } else {
            expandedSubscriptionIDs.insert(id)
        }
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func subscriptionSummary(for source: SubscriptionSource) -> String {
        let importedCount = viewModel.importedConnectionCount(for: source.id)
        let configText = importedCount == 1 ? "1 config" : "\(importedCount) configs"
        let intervalText: String

        if let interval = source.autoUpdateIntervalMinutes, interval > 0 {
            intervalText = "auto \(formattedInterval(interval))"
        } else {
            intervalText = "auto off"
        }

        if let lastRefreshedAt = source.lastRefreshedAt {
            return "\(configText) • \(intervalText) • updated \(lastRefreshedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "\(configText) • \(intervalText)"
    }

    private func formattedInterval(_ minutes: Int) -> String {
        if minutes % 1440 == 0 {
            let days = minutes / 1440
            return days == 1 ? "every day" : "every \(days)d"
        }

        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "hourly" : "every \(hours)h"
        }

        return "every \(minutes)m"
    }
}

private struct QRPayload: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

private struct ShareMenuPayload: Equatable {
    let title: String
    let value: String
}

private struct ShareActionPopover: View {
    let onCopy: () -> Void
    let onShowQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                onCopy()
            } label: {
                Label("Copy connection", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                onShowQR()
            } label: {
                Label("Show QR", systemImage: "qrcode")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 180)
    }
}

private struct SubscriptionSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let source: SubscriptionSource
    let onSave: (String, String, Int?) -> Void

    @State private var customName: String
    @State private var urlString: String
    @State private var selectedIntervalMinutes: Int?

    private let intervalOptions: [Int?] = [nil, 5, 15, 30, 60, 180, 360, 720, 1440]

    init(source: SubscriptionSource, onSave: @escaping (String, String, Int?) -> Void) {
        self.source = source
        self.onSave = onSave
        _customName = State(initialValue: source.title)
        _urlString = State(initialValue: source.urlString)
        _selectedIntervalMinutes = State(initialValue: source.autoUpdateIntervalMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscription settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline.weight(.semibold))

                TextField("Custom name", text: $customName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Subscription URL")
                    .font(.subheadline.weight(.semibold))

                TextField("https://subscription…", text: $urlString)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Auto update")
                    .font(.subheadline.weight(.semibold))

                Picker("Auto update interval", selection: $selectedIntervalMinutes) {
                    ForEach(intervalOptions, id: \.self) { option in
                        Text(intervalLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    onSave(customName, urlString, selectedIntervalMinutes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func intervalLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "Off" }
        switch minutes {
        case 5:
            return "Every 5 minutes"
        case 15:
            return "Every 15 minutes"
        case 30:
            return "Every 30 minutes"
        case 60:
            return "Every hour"
        case 180:
            return "Every 3 hours"
        case 360:
            return "Every 6 hours"
        case 720:
            return "Every 12 hours"
        case 1440:
            return "Every day"
        default:
            return "Every \(minutes) minutes"
        }
    }
}

private struct QRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let payload: QRPayload

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Text(payload.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if let image = qrImage {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                    )
            } else {
                ContentUnavailableView("QR unavailable", systemImage: "qrcode")
            }

            Text(payload.value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                Spacer()

                Button("Copy connection") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(payload.value, forType: .string)
                }

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var qrImage: NSImage? {
        filter.message = Data(payload.value.utf8)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
    }
}

#Preview {
    SettingsView(viewModel: AppViewModel())
}
