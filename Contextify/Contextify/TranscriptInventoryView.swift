import SwiftUI
import ContextifyCore

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor
  let onSelectSession: (TranscriptSession) -> Void

  @State private var selectedSessionURL: URL?
  @State private var searchText = ""
  @State private var groupingMode: GroupingMode = .provider
  @State private var metadata: [URL: TranscriptMetadata] = [:]
  @State private var loadingMetadata: Set<URL> = []

  enum GroupingMode: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case date = "Date"
    case flat = "All"

    var id: String { rawValue }
  }

  var body: some View {
    Group {
      if let error = monitor.lastError, monitor.allSessions.isEmpty {
        // Show error when no transcripts found
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("Unable to Load Transcripts")
            .font(.headline)
          Text(error)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HSplitView {
          // Session list
          sessionListView
            .frame(minWidth: 250)

          // Detail view
          detailView
            .frame(minWidth: 500)
        }
      }
    }
  }

  private var selectedSession: TranscriptSession? {
    guard let url = selectedSessionURL else { return nil }
    return monitor.allSessions.first(where: { $0.fileURL == url })
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
      List(monitor.allSessions, id: \.fileURL, selection: $selectedSessionURL) { session in
        sessionRow(session)
          .tag(session.fileURL)
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
      .onChange(of: monitor.allSessions) { _, newSessions in
        // Clear selection if selected session no longer exists
        if let selectedURL = selectedSessionURL,
           !newSessions.contains(where: { $0.fileURL == selectedURL }) {
          selectedSessionURL = nil
        }

        // Load metadata for new sessions
        Task {
          await loadMetadataForSessions(newSessions)
        }
      }
      .task {
        // Load metadata on initial appearance
        await loadMetadataForSessions(monitor.allSessions)
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let session = selectedSession {
      TranscriptDetailView(
        session: session,
        isActive: session.fileURL == monitor.activeSession?.fileURL,
        onSelect: {
          onSelectSession(session)
        },
        onMetadataUpdate: { url, newMetadata in
          metadata[url] = newMetadata
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

        if let meta = metadata[session.fileURL] {
          Text(meta.title)
            .font(.callout)
            .lineLimit(1)
        } else if loadingMetadata.contains(session.fileURL) {
          HStack(spacing: 4) {
            ProgressView()
              .controlSize(.mini)
              .scaleEffect(0.7)
            Text("Analyzing… (~3s)")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(session.identifier)
            .font(.callout)
            .lineLimit(1)
        }

        Spacer()

        if session.fileURL == monitor.activeSession?.fileURL {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.green)
        }
      }

      if let meta = metadata[session.fileURL] {
        // Description (2 lines)
        Text(meta.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
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

        Spacer()

        // Topic chips (max 2)
        if let meta = metadata[session.fileURL] {
          HStack(spacing: 4) {
            ForEach(meta.topics.prefix(2), id: \.self) { topic in
              Text(topic)
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())
            }
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  // MARK: - Helpers

  private var filteredSessions: [TranscriptSession] {
    let sessions = monitor.allSessions
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
    // Refresh handled by window wrapper via monitor.refresh()
  }

  private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
    for session in sessions {
      // Skip if already loaded or loading
      guard metadata[session.fileURL] == nil,
            !loadingMetadata.contains(session.fileURL) else {
        continue
      }

      // Check for cached metadata first
      let store = SidecarMetadataStore()
      if let cached = try? store.load(for: session.fileURL) {
        metadata[session.fileURL] = cached
        continue
      }

      // Trigger generation
      loadingMetadata.insert(session.fileURL)

      Task {
        do {
          let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
          metadata[session.fileURL] = generated
          loadingMetadata.remove(session.fileURL)
        } catch {
          // Failed to generate, remove loading indicator
          loadingMetadata.remove(session.fileURL)
        }
      }
    }
  }
}

/// Detail view for a selected transcript session
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onSelect: () -> Void
  let onMetadataUpdate: ((URL, TranscriptMetadata) -> Void)?

  @State private var metadata: TranscriptMetadata?
  @State private var isRegenerating = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with status badge
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            // Use metadata title if available, otherwise fall back to identifier
            Text(metadata?.title ?? session.identifier)
              .font(.title2)
              .fontWeight(.semibold)

            // Show description if available, otherwise show provider + filename
            if let meta = metadata, !meta.description.isEmpty {
              Text(meta.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            } else {
              Text("\(providerName) • \(session.fileURL.lastPathComponent)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
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

        // AI-Generated Metadata
        if let meta = metadata {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("AI Summary")
                .font(.headline)

              if meta.needsReview {
                Text("Needs Review")
                  .font(.caption)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.orange)
                  .clipShape(Capsule())
              }

              if meta.promptVersion < 2 {
                Text("Stale")
                  .font(.caption)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.yellow)
                  .clipShape(Capsule())
              }

              Spacer()

              Button {
                Task {
                  await regenerateMetadata()
                }
              } label: {
                HStack(spacing: 4) {
                  if isRegenerating {
                    ProgressView()
                      .controlSize(.mini)
                  } else {
                    Image(systemName: "arrow.clockwise")
                  }
                  Text("Regenerate")
                }
                .font(.caption)
              }
              .buttonStyle(.bordered)
              .disabled(isRegenerating)
            }

            metadataRow(label: "Title", value: meta.title)
            metadataRow(label: "Description", value: meta.description)

            HStack(alignment: .top) {
              Text("Topics")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

              HStack(spacing: 6) {
                ForEach(meta.topics, id: \.self) { topic in
                  Text(topic)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                }
              }
            }

            metadataRow(label: "Confidence", value: String(format: "%.2f", meta.confidence))
            metadataRow(label: "Generated", value: formattedDate(meta.generatedAt))
            metadataRow(label: "Strategy", value: meta.strategy)
            metadataRow(label: "Model", value: meta.model)
            metadataRow(label: "Messages", value: "\(meta.messageCount)")
            metadataRow(label: "Latency", value: "\(meta.latencyMs)ms")
          }

          Divider()
        } else {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("AI Summary")
                .font(.headline)
              Spacer()
              ProgressView()
                .controlSize(.mini)
            }
            Text("Generating metadata…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Divider()
        }

        // File Metadata
        VStack(alignment: .leading, spacing: 12) {
          Text("File Info")
            .font(.headline)

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
    .task(id: session.fileURL) {
      // Load metadata on appearance or when session changes
      await loadMetadata()
    }
  }

  private func loadMetadata() async {
    let store = SidecarMetadataStore()
    metadata = try? store.load(for: session.fileURL)

    // If no cached metadata, trigger generation
    if metadata == nil {
      do {
        metadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
      } catch {
        // Failed to generate, metadata stays nil
      }
    }
  }

  private func regenerateMetadata() async {
    isRegenerating = true
    defer { isRegenerating = false }

    do {
      let newMetadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
        for: session,
        forceRegenerate: true
      )
      metadata = newMetadata

      // Notify parent view to update list
      onMetadataUpdate?(session.fileURL, newMetadata)
    } catch {
      // Failed to regenerate, keep existing metadata
    }
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
    TranscriptInventoryView { _ in
      // Session selection handler
    }
    .environment(ConversationMonitor.shared)
  }
}
#endif
