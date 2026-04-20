//
//  ContentView.swift
//  teleport
//
//  Created by Michael Chernigin on 21.04.2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("teleport")
                .font(.title2.bold())
            Text("This app runs from the menu bar. Open the status item to configure your VLESS link and control Xray.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 360)
    }
}

#Preview {
    ContentView()
}
