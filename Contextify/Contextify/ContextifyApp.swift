//
//  ContextifyApp.swift
//  Contextify
//
//  Created by Rob Banagale on 9/13/25.
//

import SwiftUI
import AppKit

@main
struct ContextifyApp: App {
    private let model = HUDViewModel.shared
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .commands { ProjectRootCommands() }
    }
}

struct ProjectRootCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Set Project Root…") { pickProjectRoot() }
        }
    }
    private func pickProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.urls.first {
            _ = HUDViewModel.shared.setProjectRoot(url: url)
        }
    }
}
