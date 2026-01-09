//
//  ASOApp.swift
//  ASO
//

import SwiftUI

@main
struct ASOApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Data") {
                Button("Refresh All Rankings") {
                    Task {
                        await DataStore.shared.refreshAllRankings()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        #endif
    }
}
