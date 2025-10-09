import SwiftUI
import ContextifyCore

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  let sessions: [TranscriptSession]
  let activeSessionURL: URL?
  let onSelectSession: (TranscriptSession) -> Void
  let onDismiss: () -> Void

  @State private var selectedSessionURL: URL?
  @State private var searchText = ""
  @State private var groupingMode: GroupingMode = .provider

  enum GroupingMode: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case date = "Date"
    case flat = "All"

    var id: String { rawValue }
  }

  var body: some View {
    HSplitView {
      // Session list
      sessionListView
        .frame(minWidth: 250)

      // Detail view
      detailView
        .frame(minWidth: 500)
    }
    .frame(minWidth: 800, minHeight: 600)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done") {
          onDismiss()
        }
        .keyboardShortcut(.cancelAction)
      }
    }
  }

  private var selectedSession: TranscriptSession? {
    guard let url = selectedSessionURL else { return nil }
    return sessions.first(where: { $0.fileURL == url })
  }

  @ViewBuilder
  private var sessionListView: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Transcript Inventory")
          .font(.headline)
        Spacer()
        Button {
          refreshSessions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
      }
      .padding()

      // Toolbar with grouping
      HStack {
        Picker("Group by", selection: $groupingMode) {
          ForEach(GroupingMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        Spacer()

        Text("\(filteredSessions.count) transcripts")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Session list with URL-based selection
      List(sessions, id: \.fileURL, selection: $selectedSessionURL) { session in
        sessionRow(session)
          .tag(session.fileURL)
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
      .onChange(of: sessions) { _, newSessions in
        // Clear selection if selected session no longer exists
        if let selectedURL = selectedSessionURL,
           !newSessions.contains(where: { $0.fileURL == selectedURL }) {
          selectedSessionURL = nil
        }
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let session = selectedSession {
      TranscriptDetailView(
        session: session,
        isActive: session.fileURL == activeSessionURL,
        onSelect: {
          onSelectSession(session)
        }
      )
    } else {
      emptyDetailView
    }
  }

  private var emptyDetailView: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.text")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No Transcript Selected")
        .font(.headline)
      Text("Select a transcript from the sidebar to view details")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Session Row

  @ViewBuilder
  private func sessionRow(_ session: TranscriptSession) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: providerIcon(session.provider))
          .foregroundStyle(providerColor(session.provider))
          .frame(width: 16)

        Text(session.identifier)
          .font(.callout)
          .lineLimit(1)

        if session.fileURL == activeSessionURL {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.green)
        }
      }

      HStack(spacing: 4) {
        Label(providerName(session.provider), systemImage: providerIcon(session.provider))
          .font(.caption)
          .foregroundStyle(.secondary)
          .labelStyle(.titleOnly)

        Text("•")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(relativeTime(session.lastActivity))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }

  // MARK: - Helpers

  private var filteredSessions: [TranscriptSession] {
    if searchText.isEmpty {
      return sessions
    }
    return sessions.filter { session in
      session.identifier.localizedCaseInsensitiveContains(searchText)
        || session.fileURL.path.localizedCaseInsensitiveContains(searchText)
    }
  }

  private func providerName(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func providerIcon(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "terminal.fill"
    case .codexCLI: return "chevron.left.forwardslash.chevron.right"
    case .other: return "doc.text"
    }
  }

  private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codexCLI: return .blue
    case .other: return .gray
    }
  }

  private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func refreshSessions() {
    // Trigger refresh in parent
    // This will be wired up when integrated
  }
}

/// Detail view for a selected transcript session
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onSelect: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with status badge
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text(session.identifier)
              .font(.title2)
              .fontWeight(.semibold)

            Text(providerName)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer()

          if isActive {
            Label("Active", systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color.green)
              .clipShape(Capsule())
          }
        }

        Divider()

        // Metadata
        VStack(alignment: .leading, spacing: 12) {
          metadataRow(label: "Last Modified", value: formattedDate(session.lastActivity))
          metadataRow(label: "File Path", value: session.fileURL.path)
          metadataRow(label: "File Name", value: session.fileURL.lastPathComponent)
          metadataRow(label: "Provider", value: providerName)

          if let fileSize = fileSize() {
            metadataRow(label: "File Size", value: fileSize)
          }

          if let lineCount = lineCount() {
            metadataRow(label: "Lines", value: "\(lineCount)")
          }
        }

        Divider()

        // Actions
        VStack(spacing: 8) {
          if !isActive {
            Button {
              onSelect()
            } label: {
              Label("Select for Monitoring", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }

          Button {
            NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSWorkspace.shared.open(session.fileURL)
          } label: {
            Label("Open in Default Editor", systemImage: "doc.text")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.fileURL.path, forType: .string)
          } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  @ViewBuilder
  private func metadataRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: 100, alignment: .leading)

      Text(value)
        .font(.subheadline)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var providerName: String {
    switch session.provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func fileSize() -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: session.fileURL.path),
          let size = attrs[.size] as? Int64 else {
      return nil
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func lineCount() -> Int? {
    guard let content = try? String(contentsOf: session.fileURL, encoding: .utf8) else {
      return nil
    }
    return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
  }
}

// MARK: - Previews

#if DEBUG
struct TranscriptInventoryView_Previews: PreviewProvider {
  static var previews: some View {
    TranscriptInventoryView(
      sessions: [
        TranscriptSession(
          provider: .claudeCode,
          identifier: "conversation-1.jsonl",
          fileURL: URL(fileURLWithPath: "/Users/rob/.claude/projects/contextify/conversation-1.jsonl"),
          lastActivity: Date()
        ),
        TranscriptSession(
          provider: .claudeCode,
          identifier: "conversation-2.jsonl",
          fileURL: URL(fileURLWithPath: "/Users/rob/.claude/projects/contextify/conversation-2.jsonl"),
          lastActivity: Date().addingTimeInterval(-3600)
        ),
        TranscriptSession(
          provider: .codexCLI,
          identifier: "session-123.jsonl",
          fileURL: URL(fileURLWithPath: "/Users/rob/.codex/sessions/session-123.jsonl"),
          lastActivity: Date().addingTimeInterval(-86400)
        )
      ],
      activeSessionURL: URL(fileURLWithPath: "/Users/rob/.claude/projects/contextify/conversation-1.jsonl"),
      onSelectSession: { _ in },
      onDismiss: { }
    )
  }
}
#endif
