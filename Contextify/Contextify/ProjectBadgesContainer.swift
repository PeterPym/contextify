import SwiftUI
import ContextifyCore
import GRDB

/// Container view that queries providers from database and displays badges
struct ProjectBadgesContainer: View {
  let projectPath: String
  @State private var providers: Set<DiscoveredProject.Provider> = []

  var body: some View {
    ProjectBadgesView(providers: providers)
      .task(id: projectPath) {
        await loadProviders()
      }
  }

  private func loadProviders() async {
    do {
      // Query database for providers
      let db = try DatabaseManager.shared.pool
      let metadata = try await db.read { db in
        let sql = """
          SELECT GROUP_CONCAT(DISTINCT t.provider) AS providers
          FROM projects p
          LEFT JOIN transcripts t ON t.project_id = p.id
          WHERE p.root_path = ?
          GROUP BY p.id
          """

        guard let row = try Row.fetchOne(db, sql: sql, arguments: [projectPath]) else {
          return Set<DiscoveredProject.Provider>()
        }

        // Parse provider set from CSV of raw values
        let providersCSV: String? = row["providers"]
        var result: Set<DiscoveredProject.Provider> = []
        if let csv = providersCSV, !csv.isEmpty {
          for token in csv.split(separator: ",") {
            let raw = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            if let p = DiscoveredProject.Provider(rawValue: raw) {
              result.insert(p)
            } else {
              result.insert(.other)
            }
          }
        }
        return result
      }

      providers = metadata
    } catch {
      // Silently fail - just don't show badges
      providers = []
    }
  }
}

#Preview {
  ProjectBadgesContainer(projectPath: "/Users/rob/code/projects/contextify")
}
