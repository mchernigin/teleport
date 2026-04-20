//
//  teleportApp.swift
//  teleport
//
//  Created by Michael Chernigin on 21.04.2026.
//

import SwiftUI

@main
struct teleportApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra("teleport", systemImage: menuBarIcon) {
            MenuBarView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch viewModel.connectionPhase {
        case .running:
            return "bolt.horizontal.circle.fill"
        case .starting, .stopping:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .ready, .stopped:
            return "bolt.horizontal.circle"
        case .unconfigured:
            return "bolt.slash.circle"
        }
    }
}
