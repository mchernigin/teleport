//
//  TeleportApp.swift
//  teleport
//
//  Created by Michael Chernigin on 21.04.2026.
//

import SwiftUI

@main
struct TeleportApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            MenuBarIconView(phase: viewModel.connectionPhase, proxyPhase: viewModel.proxyPhase)
        }
        .menuBarExtraStyle(.window)
    }
}
