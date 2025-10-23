import SwiftUI
import ContextifyCore

/// Window-specific container for TranscriptInventoryView
/// Provides window-appropriate toolbar and data binding
@MainActor
struct TranscriptInventoryWindow: View {
  @Environment(ConversationMonitor.self) private var monitor
  @AppStorage("inventoryScope") private var selectedScopeRaw = InventoryScope.conversations.rawValue
  @State private var selectedScope: InventoryScope = .conversations
  @State private var scopeCounts: (conversations: Int, metadata: Int, all: Int) = (0, 0, 0)

  var body: some View {
    TranscriptInventoryView(
      selectedScope: $selectedScope,
      scopeCounts: $scopeCounts,
      onSelectSession: { session in
        Task { @MainActor in
          await monitor.switchToSessionFromUser(session)
        }
      }
    )
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Picker("Type", selection: $selectedScope) {
          Text("Conversations\(countSuffix(.conversations))").tag(InventoryScope.conversations)
          Text("Metadata\(countSuffix(.metadata))").tag(InventoryScope.metadata)
          Text("All\(countSuffix(.all))").tag(InventoryScope.all)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .accessibilityLabel("Transcript type filter")
      }

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
    .onChange(of: selectedScope) { _, newScope in
      selectedScopeRaw = newScope.rawValue
    }
    .onAppear {
      selectedScope = InventoryScope(rawValue: selectedScopeRaw) ?? .conversations
    }
    .task {
      // Load sessions from database when window appears
      await monitor.loadAllSessionsFromDatabase()
    }
  }

  private func countSuffix(_ scope: InventoryScope) -> String {
    let count: Int
    switch scope {
    case .conversations: count = scopeCounts.conversations
    case .metadata: count = scopeCounts.metadata
    case .all: count = scopeCounts.all
    }
    return count > 0 ? " (\(count))" : ""
  }
}
