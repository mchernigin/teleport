import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSection: SettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            selectedSectionView
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle((selectedSection ?? .general).title)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selectedSection ?? .general {
        case .general:
            GeneralSettingsView(viewModel: viewModel)
        case .connections:
            ConnectionsSettingsView(viewModel: viewModel)
        case .routing:
            RoutingSettingsView()
        case .nerdShit:
            NerdShitSettingsView(viewModel: viewModel)
        case .about:
            AboutSettingsView()
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            connectionModeSection
            Spacer(minLength: 0)
        }
    }

    private var connectionModeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mode")
                    .font(.subheadline.weight(.semibold))

                Picker(
                    "Mode",
                    selection: Binding(
                        get: { viewModel.connectionMode },
                        set: { viewModel.selectConnectionMode($0) }
                    )
                ) {
                    ForEach(ConnectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(!viewModel.canChangeSelection)
            }

            Text(viewModel.connectionMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct NerdShitSettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedLog: NerdLogFile = .systemProxy
    @State private var logText = ""
    @State private var logMetadata = ""

    private let maxLogBytes: UInt64 = 256 * 1024

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsSection
            logSection
        }
        .onAppear {
            selectedLog = viewModel.connectionMode == .vpn ? .vpn : .systemProxy
            refreshLog()
        }
        .onChange(of: selectedLog) { _, _ in
            refreshLog()
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stats")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 10) {
                statCard("Status", viewModel.statusSummary)
                statCard("Mode", viewModel.connectionMode.displayName)
                statCard("Connection", viewModel.selectedConnection?.configuration.displayName ?? "None")
                statCard("Phase", "Xray: \(viewModel.connectionPhase.rawValue) • Proxy: \(viewModel.proxyPhase.rawValue)")
                statCard("Connections", "\(viewModel.savedConnections.count) saved • \(viewModel.subscriptionSources.count) subs")
                statCard("Local proxy", "HTTP :\(viewModel.proxyEndpoint.httpPort) • SOCKS :\(viewModel.proxyEndpoint.socksPort)")
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Xray logs")
                .font(.headline)

            HStack(spacing: 10) {
                Picker("Log", selection: $selectedLog) {
                    ForEach(NerdLogFile.allCases) { logFile in
                        Text(logFile.title).tag(logFile)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 460, alignment: .leading)

                Spacer(minLength: 8)

                Menu {
                    Button("Refresh") {
                        refreshLog()
                    }

                    Button("Copy Log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(logText, forType: .string)
                    }
                    .disabled(logText.isEmpty)

                    Button("Open Logs Folder") {
                        NSWorkspace.shared.open(NerdLogFile.applicationSupportDirectoryURL)
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
                .fixedSize()
            }

            Text(logMetadata)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            LogTextViewer(text: logText)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func refreshLog() {
        let url = selectedLog.url
        logText = readTail(from: url)
        logMetadata = metadata(for: url)
    }

    private func readTail(from url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > maxLogBytes ? fileSize - maxLogBytes : 0
        try? handle.seek(toOffset: offset)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""

        if offset > 0 {
            return "… showing last \(ByteCountFormatter.string(fromByteCount: Int64(maxLogBytes), countStyle: .file)) …\n" + text
        }
        return text
    }

    private func metadata(for url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "Missing: \(url.path)"
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = attributes[.modificationDate] as? Date
        let modifiedText = modified.map { Self.metadataDateFormatter.string(from: $0) } ?? "unknown"
        return "\(url.path) • \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) • modified \(modifiedText)"
    }

    private static let metadataDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct LogTextViewer: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = displayText

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let nextText = displayText
        guard textView.string != nextText else { return }

        let visibleRect = scrollView.contentView.bounds
        textView.string = nextText
        textView.scrollToVisible(visibleRect)
    }

    private var displayText: String {
        text.isEmpty ? "No log output yet." : text
    }

    final class Coordinator {
        weak var textView: NSTextView?
    }
}

private enum NerdLogFile: String, CaseIterable, Identifiable, Hashable {
    case systemProxy
    case vpn
    case vpnControl

    var id: Self { self }

    var title: String {
        switch self {
        case .systemProxy:
            return "System Proxy"
        case .vpn:
            return "VPN"
        case .vpnControl:
            return "VPN Control"
        }
    }

    var url: URL {
        switch self {
        case .systemProxy:
            return Self.applicationSupportDirectoryURL.appendingPathComponent("xray.log")
        case .vpn:
            return Self.applicationSupportDirectoryURL.appendingPathComponent("xray-tun.log")
        case .vpnControl:
            return Self.applicationSupportDirectoryURL.appendingPathComponent("xray-tun-control.log")
        }
    }

    static var applicationSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("teleport", isDirectory: true)
    }
}

private struct RoutingSettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Comming soon",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            description: Text("Routing controls will live here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case connections
    case routing
    case nerdShit
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .connections:
            return "Connections"
        case .routing:
            return "Routing"
        case .nerdShit:
            return "Nerd shit"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .connections:
            return "link"
        case .routing:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .nerdShit:
            return "terminal"
        case .about:
            return "info.circle"
        }
    }
}

#Preview {
    SettingsView(viewModel: AppViewModel())
}
