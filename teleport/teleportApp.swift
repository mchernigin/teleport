//
//  TeleportApp.swift
//  teleport
//
//  Created by Michael Chernigin on 21.04.2026.
//

import AppKit
import SwiftUI

final class TeleportAppDelegate: NSObject, NSApplicationDelegate {
    var cleanupHandler: (() -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanupHandler?()
        return .terminateNow
    }
}

@main
struct TeleportApp: App {
    @NSApplicationDelegateAdaptor(TeleportAppDelegate.self) private var appDelegate
    @StateObject private var viewModel: AppViewModel

    init() {
        let viewModel = AppViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        appDelegate.cleanupHandler = {
            viewModel.handleAppTermination()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
        } label: {
            MenuBarIconView(phase: viewModel.connectionPhase, proxyPhase: viewModel.proxyPhase)
        }
        .menuBarExtraStyle(.window)
    }
}
