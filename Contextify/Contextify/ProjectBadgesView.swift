import SwiftUI
import ContextifyCore

/// Displays provider badges for a project (Claude Code, Codex)
struct ProjectBadgesView: View {
  let projectPath: String
  @State private var providers: Set<DiscoveredProject.Provider> = []

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(providers.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
        Text(provider.icon)
          .font(.caption2)
          .help(provider.displayName)
      }
    }
    .task {
      await detectProviders()
    }
  }

  private func detectProviders() async {
    var detected: Set<DiscoveredProject.Provider> = []

    // Check for Claude Code
    let projectURL = URL(fileURLWithPath: projectPath)
    let claudeDirName = projectPath.replacingOccurrences(of: "/", with: "-")
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".claude/projects")
      .appendingPathComponent(claudeDirName)

    if FileManager.default.fileExists(atPath: claudeDir.path) {
      detected.insert(.claudeCode)
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
        detected.insert(.codex)
      }
    }

    providers = detected
  }
}

#Preview {
  ProjectBadgesView(projectPath: "/Users/rob/code/projects/contextify")
}
