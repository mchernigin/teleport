import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedSection: SettingsSection? = .connections

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
                .navigationTitle((selectedSection ?? .connections).title)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    @ViewBuilder
    private var selectedSectionView: some View {
        switch selectedSection ?? .connections {
        case .connections:
            ConnectionsSettingsView(viewModel: viewModel)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case connections

    var id: Self { self }

    var title: String {
        switch self {
        case .connections:
            return "Connections"
        }
    }

    var systemImage: String {
        switch self {
        case .connections:
            return "link"
        }
    }
}

#Preview {
    SettingsView(viewModel: AppViewModel())
}
