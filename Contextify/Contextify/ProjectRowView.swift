import SwiftUI
import ContextifyCore

/// Individual project row in the Projects window
struct ProjectRowView: View {
  @Environment(ConversationMonitor.self) private var monitor  // v23: for follow status

  let project: DiscoveredProject
  let onSetAsCurrent: () -> Void
  let onRevealInFinder: () -> Void
  let onShowStats: () -> Void

  // Info popover state
  @State private var showFollowModeInfo = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header: icon + name + current badge + error indicator
      HStack(spacing: 8) {
        Image(systemName: project.isCurrent ? "folder.fill" : "folder")
          .foregroundStyle(project.isCurrent ? .blue : .secondary)
          .imageScale(.large)

        Text(project.name)
          .font(.headline)

        if project.isCurrent {
          Text("CURRENT")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue)
            .cornerRadius(3)
        }

        if project.ingestionError != nil {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .imageScale(.small)
            .help("Ingestion error occurred")
        }

        // v23: Follow chip with info button
        if project.isCurrent, monitor.activeSession != nil {
          HStack(spacing: 4) {
            Menu {
              Button("Follow Newest (Auto)") {
                Task {
                  await monitor.unpinToAuto()
                }
              }
              // R6: Only show "Pin Current Session" when in auto mode (avoid redundant action)
              if !monitor.isPinnedMode, monitor.activeSession != nil {
                Button("Pin Current Session") {
                  Task {
                    if let session = monitor.activeSession {
                      await monitor.pinAndSwitch(session)
                    }
                  }
                }
              }
            } label: {
              HStack(spacing: 4) {
                Image(systemName: "paperclip")
                  .imageScale(.small)
                Text(monitor.isPinnedMode ? "Follow: Pinned" : "Follow: Auto")  // P0-4: Bound to observable state
                  .font(.caption2)
              }
              .foregroundStyle(.secondary)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color.secondary.opacity(0.1))
              .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)  // P2-2: Accessibility - ensure ≥44pt hit target
            .help("Configure active session following")

            // Info button for follow mode explanation
            InfoButton(isPresented: $showFollowModeInfo)
              .popover(isPresented: $showFollowModeInfo) {
                InfoPopoverContent(
                  title: "Follow Modes",
                  message: followModeExplanation
                )
              }
          }
        }

        Spacer()
      }

      // Path
      Text(project.path.path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)

      // Provider badges
      HStack(spacing: 8) {
        ForEach(Array(project.providers.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { provider in
          HStack(spacing: 4) {
            Image(provider.iconImage)
              .renderingMode(.template)
              .foregroundStyle(providerColor(provider))
              .imageScale(.small)
            Text(provider.displayName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.1))
          .cornerRadius(4)
        }
      }

      // Stats
      HStack(spacing: 12) {
        Label("\(project.transcriptCount) transcripts", systemImage: "doc.text")
          .font(.caption)
          .foregroundStyle(.secondary)

        if let lastActivity = project.lastActivity {
          Text("•")
            .foregroundStyle(.tertiary)
          Text("Last activity: \(lastActivity, style: .relative)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Divider()

      // Actions
      HStack(spacing: 12) {
        if !project.isCurrent {
          Button(action: onSetAsCurrent) {
            HStack(spacing: 4) {
              Image(systemName: "checkmark.circle")
                .imageScale(.small)
              Text("Set as Current")
            }
          }
          .buttonStyle(.bordered)
        }

        Button(action: onRevealInFinder) {
          HStack(spacing: 4) {
            Image(systemName: "folder")
              .imageScale(.small)
            Text("Reveal in Finder")
          }
        }
        .buttonStyle(.bordered)

        Spacer()

        Button(action: onShowStats) {
          Image(systemName: "chart.bar")
            .imageScale(.large)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("View Statistics")
        .accessibilityLabel(Text("View statistics for \(project.name)"))
      }
    }
    .padding()
    .background(Color.secondary.opacity(project.isCurrent ? 0.08 : 0.03))
    .cornerRadius(8)
  }

  // MARK: - Info Popover Content

  /// Explanation of Auto vs Pinned follow modes
  private var followModeExplanation: String {
    """
    Contextify can follow transcript sessions in two modes:

    Auto Mode (Follow Newest):
    • Automatically switches to the newest transcript session
    • Timeline updates when you start a new Claude Code/Codex session
    • Best for active development with multiple sessions

    Pinned Mode (Follow Specific):
    • Stays locked to a specific transcript session
    • Timeline doesn't switch even if newer sessions exist
    • Best for reviewing or analyzing a particular conversation

    Current mode: \(monitor.isPinnedMode ? "Pinned" : "Auto")

    Change modes using the menu to the left of this info button.
    """
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
  ProjectRowView(
    project: DiscoveredProject(
      id: "/Users/rob/code/projects/contextify",
      name: "contextify",
      path: URL(fileURLWithPath: "/Users/rob/code/projects/contextify"),
      providers: [.claudeCode, .codexCLI],
      transcriptCount: 24,
      entryCount: 1247,
      lastActivity: Date().addingTimeInterval(-300),
      isCurrent: true
    ),
    onSetAsCurrent: {},
    onRevealInFinder: {},
    onShowStats: {}
  )
  .padding()
}
