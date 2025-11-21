import SwiftUI
import ContextifyCore

/// Displays provider badges for a project (Claude Code, Codex)
/// Uses database-backed provider information instead of filesystem detection
struct ProjectBadgesView: View {
  @Environment(\.colorScheme) private var colorScheme
  let providers: Set<DiscoveredProject.Provider>

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(providers.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
        Image(provider.iconImage)
          .renderingMode(.template)
          .foregroundStyle(providerColor(provider))
          .shadow(
            color: needsShadow(provider) ? .black.opacity(0.7) : .clear,
            radius: 0.5
          )
          .help(provider.displayName)
      }
    }
  }

  /// White/light logos need shadow in light mode for visibility
  private func needsShadow(_ provider: DiscoveredProject.Provider) -> Bool {
    colorScheme == .light && provider == .codexCLI
  }

  private func providerColor(_ provider: DiscoveredProject.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codexCLI: return .white
    case .other: return .gray  // T2: Safe fallback for unknown providers
    }
  }
}

#Preview {
  ProjectBadgesView(providers: [.claudeCode, .codexCLI])
}
