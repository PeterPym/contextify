import SwiftUI
import ContextifyCore
import OSLog

/// Container view that queries providers from database and displays badges
struct ProjectBadgesContainer: View {
  let projectPath: String
  @State private var providers: Set<DiscoveredProject.Provider> = []
  private let log = Logger(subsystem: "dev.contextify", category: "ProjectBadges")

  var body: some View {
    ProjectBadgesView(providers: providers)
      .task(id: projectPath) {
        await loadProviders()
      }
  }

  private func loadProviders() async {
    do {
      if Task.isCancelled { return }

      // Query providers via orchestrator
      let orchestrator = TranscriptOrchestrator.shared
      let set = try await orchestrator.getProviders(forProjectPath: projectPath)

      if Task.isCancelled { return }
      await MainActor.run { self.providers = set }
    } catch {
      log.error("Provider badge query failed for \(projectPath, privacy: .public): \(error.localizedDescription)")
      await MainActor.run { self.providers = [] }
    }
  }
}

#Preview {
  ProjectBadgesContainer(projectPath: "/Users/rob/code/projects/contextify")
}
