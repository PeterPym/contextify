import SwiftUI
import AppKit
import ContextifyCore

@main
struct ContextifyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let model = HUDViewModel.shared

  var body: some Scene {
    Window("Contextify", id: "main") {
      ContentView()
        .environment(model)
        .background(WindowAccessor())
    }
    .defaultSize(width: 640, height: 360)
    .commands {
      CommandGroup(replacing: .newItem) { }
      ProjectRootCommands()
    }
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
