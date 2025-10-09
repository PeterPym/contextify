import SwiftUI
import ContextifyCore

/// Window-specific container for TranscriptInventoryView
/// Provides window-appropriate toolbar and data binding
@MainActor
struct TranscriptInventoryWindow: View {
  @Environment(ConversationMonitor.self) private var monitor

  var body: some View {
    TranscriptInventoryView { session in
      Task { @MainActor in
        await monitor.switchToSessionFromUser(session)
      }
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { @MainActor in
            await monitor.refresh()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    }
  }
}
