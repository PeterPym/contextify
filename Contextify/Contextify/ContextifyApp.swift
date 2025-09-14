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
    @State private var model = HUDViewModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .commands { ProjectRootCommands() }
    }
}

struct ProjectRootCommands: Commands {
    @Environment(HUDViewModel.self) private var model
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
            model.setProjectRoot(url: url)
        }
    }
}
