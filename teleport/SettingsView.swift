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

#Preview {
    SettingsView(viewModel: AppViewModel())
}
