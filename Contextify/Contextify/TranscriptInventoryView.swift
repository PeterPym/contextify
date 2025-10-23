import SwiftUI
import ContextifyCore
import OSLog

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor
  @Environment(DeveloperMode.self) private var devMode
  @Environment(HUDViewModel.self) private var hudViewModel
  let onSelectSession: (TranscriptSession) -> Void

  @State private var selectedTranscriptId: String?  // Changed from URL to transcript ID
  @State private var searchText = ""
  @State private var debouncedSearch = ""  // Debounced search for filtering
  @State private var debounceTask: Task<Void, Never>?
  @State private var showOnlyMetadata = false  // Filter toggle: when true, shows only metadata-only transcripts
  @State private var showingMetadataHelp = false  // Info popover visibility
  @State private var metadata: [String: TranscriptMetadata] = [:]  // Changed key from URL to transcript ID
  @State private var loadingMetadata: Set<String> = []  // Changed from URL to transcript ID
  @State private var metadataTasks: [String: Task<Void, Never>] = [:]  // Track background tasks for cancellation
  @State private var showingFlushAlert = false
  @State private var lastFlushCount = 0

  private let log = Logger(subsystem: "dev.contextify", category: "TranscriptInventoryView")

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
    guard let id = selectedTranscriptId else { return nil }
    return monitor.allSessions.first(where: { $0.identifier == id })
  }

  @ViewBuilder
  private var sessionListView: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            if let projectName = hudViewModel.projectRootURL?.lastPathComponent {
              Text("Transcript Inventory for \(projectName)")
                .font(.headline)
            } else {
              Text("Transcript Inventory")
                .font(.headline)
            }
            Text("\(filteredSessions.count) transcripts")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()

          if devMode.isEnabled {
            Button {
              flushHeuristicCache()
            } label: {
              Label("Flush Heuristic Cache", systemImage: "trash")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Delete cached metadata for \"Developer Chat\" and \"Brief Session\" titles")

            Button {
              refreshSessions()
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
          }
        }
      }
      .padding()
      .alert("Cache Flushed", isPresented: $showingFlushAlert) {
        Button("OK") { }
      } message: {
        Text("Flushed \(lastFlushCount) heuristic metadata files. The transcripts will be re-analyzed automatically.")
      }

      // Toolbar
      HStack {
        Toggle("Show only metadata transcripts", isOn: $showOnlyMetadata)
          .toggleStyle(.switch)
          .controlSize(.mini)

        Button {
          showingMetadataHelp = true
        } label: {
          Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Learn about metadata-only transcripts")
        .popover(isPresented: $showingMetadataHelp) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Metadata-Only Transcripts")
              .font(.headline)
            Text("Claude Code writes some transcript files containing only file history snapshots, system records, and other metadata without actual conversation turns.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding()
          .frame(width: 280)
        }

        Spacer()
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Session list with transcript ID-based selection (FIXED: use filteredSessions)
      List(filteredSessions, id: \.identifier, selection: $selectedTranscriptId) { session in
        sessionRow(session)
          .tag(session.identifier)
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
      .onChange(of: searchText) { _, newValue in
        // Debounce search input (300ms)
        debounceTask?.cancel()
        debounceTask = Task {
          try? await Task.sleep(for: .milliseconds(300))
          guard !Task.isCancelled else { return }
          await MainActor.run {
            debouncedSearch = newValue
          }
        }
      }
      .onChange(of: monitor.allSessions) { _, newSessions in
        // Clear selection if selected session no longer exists
        if let selectedId = selectedTranscriptId,
           !newSessions.contains(where: { $0.identifier == selectedId }) {
          selectedTranscriptId = nil
        }

        // PHASE 1: Ensure discovered sessions are persisted to database
        // This prevents FK constraint errors when generating metadata
        Task {
          await persistDiscoveredSessions(newSessions)
        }

        // PHASE 2: Load metadata for new sessions (centralized, not per-row)
        Task {
          await loadMetadataForSessions(newSessions)
        }
      }
      .task {
        // Ensure sessions are persisted before loading metadata
        await persistDiscoveredSessions(monitor.allSessions)

        // Load metadata on initial appearance
        await loadMetadataForSessions(monitor.allSessions)
      }
      .onDisappear {
        // Cancel pending debounce task to prevent leaks
        debounceTask?.cancel()
        debounceTask = nil

        // Cancel all metadata generation tasks
        metadataTasks.values.forEach { $0.cancel() }
        metadataTasks.removeAll()
      }
      .onReceive(NotificationCenter.default.publisher(for: .revealTranscript)) { notification in
        guard let path = notification.userInfo?["path"] as? String else { return }

        // Find session with matching path
        if let session = monitor.allSessions.first(where: { $0.fileURL.path == path }) {
          // Select the session by ID
          selectedTranscriptId = session.identifier

          // TODO: Add scroll-to-item logic when List supports programmatic scrolling
        }
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let session = selectedSession {
      TranscriptDetailView(
        session: session,
        isActive: session.identifier == monitor.activeSession?.identifier,
        onSelect: {
          onSelectSession(session)
        },
        onMetadataUpdate: { transcriptId, newMetadata in
          metadata[transcriptId] = newMetadata
        },
        orchestrator: monitor.orchestrator
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

        if let meta = metadata[session.identifier] {
          Text(meta.title)
            .font(.callout)
            .lineLimit(1)
        } else if loadingMetadata.contains(session.identifier) {
          HStack(spacing: 4) {
            ProgressView()
              .controlSize(.mini)
              .scaleEffect(0.7)
              .frame(width: 10, height: 10)
            Text("Analyzing…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(session.identifier)
            .font(.callout)
            .lineLimit(1)
        }

        Spacer()

        if session.identifier == monitor.activeSession?.identifier {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.green)
        }
      }

      if let meta = metadata[session.identifier] {
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

        // Metadata-only indicator (when toggle is on and no conversation entries)
        if showOnlyMetadata && session.entryCount == 0 {
          Text("•")
            .font(.caption)
            .foregroundStyle(.secondary)

          Label("Metadata Only", systemImage: "doc.badge.ellipsis")
            .font(.caption)
            .foregroundStyle(.orange)
            .labelStyle(.titleOnly)
        }

        Spacer()

        // Topic chips (max 2)
        if let meta = metadata[session.identifier] {
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
    var sessions = monitor.allSessions

    // When toggle is on, show only metadata-only transcripts (entryCount == 0)
    if showOnlyMetadata {
      sessions = sessions.filter { $0.entryCount == 0 }
    }

    // Apply search filter
    if debouncedSearch.isEmpty {
      return sessions
    }

    // Search in metadata title/description if available
    return sessions.filter { session in
      if let meta = metadata[session.identifier] {
        return meta.title.localizedCaseInsensitiveContains(debouncedSearch)
          || meta.description.localizedCaseInsensitiveContains(debouncedSearch)
          || meta.topics.contains { $0.localizedCaseInsensitiveContains(debouncedSearch) }
      }
      // Fall back to identifier and path
      return session.identifier.localizedCaseInsensitiveContains(debouncedSearch)
        || session.fileURL.path.localizedCaseInsensitiveContains(debouncedSearch)
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

  private func flushHeuristicCache() {
    Task { @MainActor in
      // True SQL-backed flush: delete metadata records for heuristic entries
      guard let orchestrator = monitor.orchestrator else {
        return
      }

      var flushedCount = 0
      for session in monitor.allSessions {
        // Check if this has heuristic metadata
        if let meta = metadata[session.identifier],
           meta.model == "heuristic" ||
           meta.title == "Developer Chat" ||
           meta.title == "Brief Session" {
          // Delete from SQL
          try? orchestrator.deleteMetadata(forTranscript: session.identifier)
          metadata.removeValue(forKey: session.identifier)
          flushedCount += 1

          // Trigger regeneration
          loadingMetadata.insert(session.identifier)
          Task { @MainActor in
            defer { loadingMetadata.remove(session.identifier) }
            do {
              let newMeta = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
                for: session,
                forceRegenerate: true
              )
              metadata[session.identifier] = newMeta
            } catch {
              // Failed to regenerate, loading indicator removed by defer
            }
          }
        }
      }

      if flushedCount > 0 {
        lastFlushCount = flushedCount
        showingFlushAlert = true
      }
    }
  }

  /// Persist discovered transcript sessions to database (safety layer)
  /// This ensures transcript records exist before metadata generation attempts,
  /// preventing FK constraint errors during metadata save operations.
  @MainActor
  private func persistDiscoveredSessions(_ sessions: [TranscriptSession]) async {
    guard let orchestrator = monitor.orchestrator else {
      log.warning("Cannot persist sessions: orchestrator not available")
      return
    }

    guard !sessions.isEmpty else { return }

    // Get project root from HUDViewModel (same pattern as ConversationMonitor)
    guard let projectRoot = HUDViewModel.shared.projectRootURL else {
      log.warning("Cannot persist sessions: no project root set")
      return
    }

    log.debug("Ensuring \(sessions.count) discovered sessions are persisted to database")

    // Get or create project in database
    do {
      let projectId = try orchestrator.getOrCreateProject(
        name: projectRoot.lastPathComponent,
        rootPath: projectRoot.path
      )

      // Convert TranscriptSessions to DiscoveredTranscripts
      let discovered = sessions.map { session in
        DiscoveredTranscript(
          fileURL: session.fileURL,
          provider: session.provider.rawValue,
          sessionId: nil  // TranscriptSession doesn't have providerSessionId
        )
      }

      // Upsert to database (idempotent - safe to call multiple times)
      let resolved = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
      let newCount = resolved.filter { $0.wasCreated }.count
      if newCount > 0 {
        log.info("✅ Persisted \(resolved.count) transcripts (\(newCount) new)")
      } else {
        log.debug("All \(resolved.count) transcripts already in database")
      }
    } catch {
      log.error("Failed to persist transcripts: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
    // Centralized loading: batch fetch from SQL, then spawn Tasks only for cache misses
    guard let orchestrator = monitor.orchestrator else {
      return
    }

    // Batch fetch metadata from SQL
    let transcriptIds = sessions.map(\.identifier)
    let cachedMetadata = (try? orchestrator.getMetadataBatch(transcriptIds: transcriptIds)) ?? [:]

    // Update state with cached results
    for (transcriptId, record) in cachedMetadata {
      metadata[transcriptId] = record.toUIModel()
    }

    // Find sessions that need generation (not in cache, not already loading)
    let missingIds = Set(transcriptIds).subtracting(Set(cachedMetadata.keys)).subtracting(loadingMetadata)
    let missingSessions = sessions.filter { missingIds.contains($0.identifier) }

    // Spawn generation tasks for cache misses
    for session in missingSessions {
      let id = session.identifier
      loadingMetadata.insert(id)

      let task = Task { @MainActor in
        defer {
          loadingMetadata.remove(id)
          metadataTasks[id] = nil
        }
        do {
          let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
          metadata[id] = generated
          log.info("✅ Successfully generated metadata for \(id, privacy: .public): \(generated.title, privacy: .public)")
        } catch {
          log.error("❌ Failed to generate metadata for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
          // Failed to generate, loading indicator removed by defer
        }
      }
      metadataTasks[id] = task
    }
  }
}

/// Detail view for a selected transcript session
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onSelect: () -> Void
  let onMetadataUpdate: ((String, TranscriptMetadata) -> Void)?  // Changed from URL to transcript ID
  let orchestrator: TranscriptOrchestrator?

  @State private var metadata: TranscriptMetadata?
  @State private var isRegenerating = false

  // v7 Metadata
  @State private var fileSnapshots: [FileSnapshot] = []
  @State private var systemEvents: [SystemEvent] = []
  @State private var usageStats: UsageAggregate?

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

        // Transcript Details (File Info + LLM metadata if available)
        VStack(alignment: .leading, spacing: 12) {
          Text("Transcript Details")
            .font(.headline)

          // Include Title and Description from LLM metadata if available
          if let meta = metadata {
            metadataRow(label: "Title", value: meta.title)
            metadataRow(label: "Description", value: meta.description)
          }

          metadataRow(label: "Last Modified", value: formattedDate(session.lastActivity))

          // File Path with Finder reveal button
          HStack(alignment: .top) {
            Text("File Path")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(width: 100, alignment: .leading)

            Text(session.fileURL.path)
              .font(.subheadline)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            Button {
              NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
            } label: {
              Image(systemName: "folder")
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
          }

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
                      .frame(width: 10, height: 10)
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
                .frame(width: 10, height: 10)
            }
            Text("Generating metadata…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Divider()
        }

        // File Activity (v7 metadata)
        if !fileSnapshots.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("File Activity")
              .font(.headline)

            metadataRow(label: "Snapshots", value: "\(fileSnapshots.count)")

            if let firstSnapshot = fileSnapshots.first {
              metadataRow(label: "Last Snapshot", value: formattedTimestamp(firstSnapshot.snapshotTimestamp))
            }

            // Show most recent snapshot details
            if let snapshot = fileSnapshots.first {
              // Get tracked files for this snapshot
              if let orchestrator = orchestrator,
                 let trackedFiles = try? orchestrator.getTrackedFiles(snapshotId: snapshot.id),
                 !trackedFiles.isEmpty {
                metadataRow(label: "Tracked Files", value: "\(trackedFiles.count)")

                // Show file list (limited to 5)
                VStack(alignment: .leading, spacing: 4) {
                  ForEach(trackedFiles.prefix(5), id: \.id) { file in
                    HStack {
                      Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                      Text(file.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                      Spacer()
                      Text("v\(file.version)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }
                  }

                  if trackedFiles.count > 5 {
                    Text("+ \(trackedFiles.count - 5) more files")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
          }

          Divider()
        }

        // Usage Statistics (v7 metadata)
        if let stats = usageStats, stats.messageCount > 0 {
          VStack(alignment: .leading, spacing: 12) {
            Text("Usage Statistics")
              .font(.headline)

            metadataRow(label: "Messages", value: "\(stats.messageCount)")
            metadataRow(label: "Input Tokens", value: formatNumber(stats.totalInputTokens))
            metadataRow(label: "Output Tokens", value: formatNumber(stats.totalOutputTokens))

            if stats.totalCacheCreation > 0 {
              metadataRow(label: "Cache Creation", value: formatNumber(stats.totalCacheCreation))
            }

            if stats.totalCacheRead > 0 {
              metadataRow(label: "Cache Read", value: formatNumber(stats.totalCacheRead))
            }

            let totalTokens = stats.totalInputTokens + stats.totalOutputTokens +
                              stats.totalCacheCreation + stats.totalCacheRead
            metadataRow(label: "Total Tokens", value: formatNumber(totalTokens))
          }

          Divider()
        }

        // System Events (v7 metadata)
        if !systemEvents.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("System Events")
              .font(.headline)

            metadataRow(label: "Total Events", value: "\(systemEvents.count)")

            // Count errors
            let errorCount = systemEvents.filter { $0.level == "error" }.count
            if errorCount > 0 {
              metadataRow(label: "Errors", value: "\(errorCount)")
            }

            // Show recent events (limited to 5)
            VStack(alignment: .leading, spacing: 6) {
              ForEach(systemEvents.prefix(5), id: \.id) { event in
                HStack(alignment: .top, spacing: 8) {
                  // Level indicator
                  Image(systemName: eventIcon(event.level))
                    .font(.caption)
                    .foregroundStyle(eventColor(event.level))
                    .frame(width: 12)

                  VStack(alignment: .leading, spacing: 2) {
                    Text(event.subtype)
                      .font(.caption)
                      .fontWeight(.medium)

                    if let content = event.content {
                      Text(content)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    }

                    if let error = event.error {
                      Text("Error: \(error)")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                    }

                    Text(formattedTimestamp(event.timestamp))
                      .font(.system(size: 9))
                      .foregroundStyle(.tertiary)
                  }

                  Spacer()
                }
                .padding(.vertical, 4)
              }

              if systemEvents.count > 5 {
                Text("+ \(systemEvents.count - 5) more events")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Divider()
        }

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
    .task(id: session.identifier) {  // Changed from fileURL to identifier
      // Load metadata on appearance or when session changes
      await loadMetadata()
      await loadV7Metadata()
    }
  }

  @MainActor
  private func loadMetadata() async {
    // Load from SQL backend
    guard let orchestrator = orchestrator else {
      return
    }

    // Check SQL cache first
    if let record = try? orchestrator.getMetadata(forTranscript: session.identifier) {
      metadata = record.toUIModel()
    } else {
      // Not in cache, trigger generation
      do {
        metadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
      } catch {
        // Failed to generate, metadata stays nil
      }
    }
  }

  @MainActor
  private func regenerateMetadata() async {
    isRegenerating = true
    defer { isRegenerating = false }

    do {
      let newMetadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
        for: session,
        forceRegenerate: true
      )
      metadata = newMetadata

      // Notify parent view to update list (using transcript ID)
      onMetadataUpdate?(session.identifier, newMetadata)
    } catch {
      // Failed to regenerate, keep existing metadata
    }
  }

  @MainActor
  private func loadV7Metadata() async {
    guard let orchestrator = orchestrator else { return }

    do {
      // Load file snapshots
      fileSnapshots = try orchestrator.getFileSnapshots(transcriptId: session.identifier)

      // Load system events (limit to recent 50)
      systemEvents = try orchestrator.getSystemEvents(transcriptId: session.identifier, limit: 50)

      // Load usage statistics
      usageStats = try orchestrator.getTranscriptUsageStats(transcriptId: session.identifier)
    } catch {
      // Failed to load v7 metadata, keep empty arrays
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
    // Use database entry count instead of reading the entire file
    guard let orch = orchestrator else { return nil }

    // Use session identifier directly (it's already the database transcript ID)
    let transcriptId = session.identifier

    do {
      let entries = try orch.getEntries(forTranscript: transcriptId, afterTimestamp: nil)
      return entries.count
    } catch {
      return nil
    }
  }

  // v7 Metadata Helpers

  private func formattedTimestamp(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func formatNumber(_ number: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
  }

  private func eventIcon(_ level: String) -> String {
    switch level.lowercased() {
    case "error": return "exclamationmark.circle.fill"
    case "warning": return "exclamationmark.triangle.fill"
    case "info": return "info.circle.fill"
    default: return "circle.fill"
    }
  }

  private func eventColor(_ level: String) -> Color {
    switch level.lowercased() {
    case "error": return .red
    case "warning": return .orange
    case "info": return .blue
    default: return .secondary
    }
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
