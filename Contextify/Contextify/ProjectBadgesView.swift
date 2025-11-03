import SwiftUI
import ContextifyCore

/// Displays provider badges for a project (Claude Code, Codex)
struct ProjectBadgesView: View {
  let projectPath: String
  @State private var providers: Set<DiscoveredProject.Provider> = []

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(providers.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
        Image(provider.iconImage)
          .renderingMode(.template)
          .foregroundStyle(providerColor(provider))
          .help(provider.displayName)
      }
    }
    .task {
      await detectProviders()
    }
  }

  private func providerColor(_ provider: DiscoveredProject.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codexCLI: return .white
    }
  }

  private func detectProviders() async {
    // Run file I/O on background thread to avoid blocking main thread
    let detected = await Task.detached {
      var result: Set<DiscoveredProject.Provider> = []

      // Check for Claude Code
      let projectURL = URL(fileURLWithPath: projectPath)
      let claudeDirName = projectPath.replacingOccurrences(of: "/", with: "-")
      let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
        .appendingPathComponent(claudeDirName)

      if FileManager.default.fileExists(atPath: claudeDir.path) {
        result.insert(.claudeCode)
      }

      // Check for Codex
      let codexDir = projectURL.appendingPathComponent(".codex/sessions")
      if FileManager.default.fileExists(atPath: codexDir.path) {
        let hasFiles = (try? FileManager.default.contentsOfDirectory(
          at: codexDir,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }.isEmpty) == false

        if hasFiles {
          result.insert(.codexCLI)
        }
      }

      return result
    }.value

    providers = detected
  }
}

#Preview {
  ProjectBadgesView(projectPath: "/Users/rob/code/projects/contextify")
}
