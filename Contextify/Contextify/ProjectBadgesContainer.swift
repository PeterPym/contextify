import SwiftUI
import ContextifyCore
import GRDB
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

      // Query database for providers
      let db = try DatabaseManager.shared.pool
      let set: Set<DiscoveredProject.Provider> = try await db.read { db in
        let sql = """
          SELECT GROUP_CONCAT(DISTINCT t.provider) AS providers
          FROM projects p
          LEFT JOIN transcripts t ON t.project_id = p.id
          WHERE p.root_path = ?
          GROUP BY p.id
          """

        guard let row = try Row.fetchOne(db, sql: sql, arguments: [projectPath]) else {
          return []
        }

        // Parse provider set from CSV of raw values
        let providersCSV: String? = row["providers"]
        var result: Set<DiscoveredProject.Provider> = []
        if let csv = providersCSV, !csv.isEmpty {
          for token in csv.split(separator: ",") {
            let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            // Tolerant mapping for legacy/variant provider strings
            if let p = DiscoveredProject.Provider(dbRaw: raw) ?? DiscoveredProject.Provider(rawValue: raw) {
              result.insert(p)
            } else {
              result.insert(.other)
            }
          }
        }
        return result
      }

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
