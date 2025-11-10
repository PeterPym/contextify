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
      scopeCounts: $scopeCounts
    )
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
}
