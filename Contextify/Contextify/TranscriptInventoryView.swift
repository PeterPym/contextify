import SwiftUI
import ContextifyCore

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses NavigationSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  let sessions: [TranscriptSession]
  let activeSessionURL: URL?
  let onSelectSession: (TranscriptSession) -> Void

  @State private var selectedSession: TranscriptSession?
  @State private var searchText = ""
  @State private var groupingMode: GroupingMode = .provider

  enum GroupingMode: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case date = "Date"
    case flat = "All"

    var id: String { rawValue }
  }

  var body: some View {
    NavigationSplitView {
      sidebarContent
    } detail: {
      detailContent
    }
    .frame(minWidth: 600, minHeight: 400)
  }

  @ViewBuilder
  private var sidebarContent: some View {
    VStack(spacing: 0) {
      // Toolbar with search and grouping
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
      .padding(.vertical, 8)

      Divider()

      // Session list
      List(selection: $selectedSession) {
        switch groupingMode {
        case .provider:
          providerGroupedSessions
        case .date:
          dateGroupedSessions
        case .flat:
          flatSessions
        }
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
    }
    .navigationTitle("Transcript Inventory")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          refreshSessions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    }
  }

  @ViewBuilder
  private var detailContent: some View {
    if let session = selectedSession {
      TranscriptDetailView(session: session, isActive: session.fileURL == activeSessionURL)
    } else {
      ContentUnavailableView(
        "No Transcript Selected",
        systemImage: "doc.text",
        description: Text("Select a transcript from the sidebar to view details")
      )
    }
  }

  // MARK: - Grouping Views

  @ViewBuilder
  private var providerGroupedSessions: some View {
    let grouped = Dictionary(grouping: filteredSessions) { $0.provider }
    let sortedKeys = grouped.keys.sorted { providerName($0) < providerName($1) }

    ForEach(sortedKeys, id: \.self) { provider in
      Section(header: Text(providerName(provider))) {
        ForEach(grouped[provider] ?? [], id: \.fileURL) { session in
          sessionRow(session)
        }
      }
    }
  }

  @ViewBuilder
  private var dateGroupedSessions: some View {
    let grouped = Dictionary(grouping: filteredSessions) { session -> String in
      let calendar = Calendar.current
      if calendar.isDateInToday(session.lastActivity) {
        return "Today"
      } else if calendar.isDateInYesterday(session.lastActivity) {
        return "Yesterday"
      } else if calendar.isDate(session.lastActivity, equalTo: Date(), toGranularity: .weekOfYear) {
        return "This Week"
      } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: session.lastActivity)
      }
    }

    let sortedKeys = ["Today", "Yesterday", "This Week"]
      + grouped.keys.filter { !["Today", "Yesterday", "This Week"].contains($0) }.sorted(by: >)

    ForEach(sortedKeys.filter { grouped[$0] != nil }, id: \.self) { dateGroup in
      Section(header: Text(dateGroup)) {
        ForEach(grouped[dateGroup] ?? [], id: \.fileURL) { session in
          sessionRow(session)
        }
      }
    }
  }

  @ViewBuilder
  private var flatSessions: some View {
    ForEach(filteredSessions, id: \.fileURL) { session in
      sessionRow(session)
    }
  }

  @ViewBuilder
  private func sessionRow(_ session: TranscriptSession) -> View {
    HStack(spacing: 8) {
      // Provider icon
      Image(systemName: providerIcon(session.provider))
        .foregroundStyle(providerColor(session.provider))
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        HStack {
          Text(session.identifier)
            .font(.body)
            .lineLimit(1)

          if session.fileURL == activeSessionURL {
            Image(systemName: "circle.fill")
              .font(.system(size: 6))
              .foregroundStyle(.green)
          }
        }

        Text(relativeTime(session.lastActivity))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .contextMenu {
      Button("Select for Monitoring") {
        onSelectSession(session)
      }

      Button("Reveal in Finder") {
        NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
      }

      Divider()

      Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.fileURL.path, forType: .string)
      }
    }
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
      onSelectSession: { _ in }
    )
  }
}
#endif
