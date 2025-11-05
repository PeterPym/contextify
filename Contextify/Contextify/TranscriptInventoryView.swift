import SwiftUI
import ContextifyCore
import OSLog

/// Scope filter for transcript inventory
enum InventoryScope: String, CaseIterable, Identifiable {
  case conversations = "conversations"
  case metadata = "metadata"
  case all = "all"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .conversations: return "Conversations"
    case .metadata: return "Metadata"
    case .all: return "All"
    }
  }
}

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor
  @Environment(DeveloperMode.self) private var devMode
  @Environment(HUDViewModel.self) private var hudViewModel

  @Binding var selectedScope: InventoryScope
  @Binding var scopeCounts: (conversations: Int, metadata: Int, all: Int)
  let onSelectSession: (TranscriptSession) -> Void

  @State private var selectedTranscriptId: String?  // Changed from URL to transcript ID
  @State private var searchText = ""
  @State private var debouncedSearch = ""  // Debounced search for filtering
  @State private var debounceTask: Task<Void, Never>?
  @State private var metadata: [String: TranscriptMetadata] = [:]  // Changed key from URL to transcript ID
  @State private var loadingMetadata: Set<String> = []  // Changed from URL to transcript ID
  @State private var metadataTasks: [String: Task<Void, Never>] = [:]  // Track background tasks for cancellation
  @State private var showingFlushAlert = false
  @State private var lastFlushCount = 0
  @State private var showingDeleteConfirmation = false
  @State private var transcriptToDelete: TranscriptSession?
  @State private var showingCleanupConfirmation = false
  @State private var cleanupResult: (count: Int, ids: [String])? = nil
  @State private var showingCleanupAlert = false

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
    .task {
      updateCounts()
    }
    .onChange(of: monitor.allSessions) { _, _ in
      updateCounts()
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
            .help("Clear cached placeholder titles")

            Button {
              refreshSessions()
            } label: {
              Label("Refresh", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Refresh transcript list")

            Button {
              showingCleanupConfirmation = true
            } label: {
              Label("Clean Up Missing Files", systemImage: "trash.circle")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Delete transcript records for files that no longer exist")
          }
        }
      }
      .padding()
      .alert("Cache Flushed", isPresented: $showingFlushAlert) {
        Button("OK") { }
      } message: {
        Text("Flushed \(lastFlushCount) heuristic metadata files. The transcripts will be re-analyzed automatically.")
      }
      .alert("Delete Transcript?", isPresented: $showingDeleteConfirmation, presenting: transcriptToDelete) { session in
        Button("Cancel", role: .cancel) {
          transcriptToDelete = nil
        }
        Button("Delete", role: .destructive) {
          deleteTranscript(session)
        }
      } message: { session in
        Text("This will permanently delete the transcript '\(session.identifier)' from the database. The transcript file will remain on disk.\n\nThis action cannot be undone.")
      }
      .alert("Clean Up Missing Transcript Files?", isPresented: $showingCleanupConfirmation) {
        Button("Cancel", role: .cancel) { }
        Button("Clean Up", role: .destructive) {
          performCleanup()
        }
      } message: {
        Text("This will scan all transcripts and delete records for files that no longer exist on disk.\n\nThis action cannot be undone.")
      }
      .alert("Cleanup Complete", isPresented: $showingCleanupAlert) {
        Button("OK") {
          cleanupResult = nil
        }
      } message: {
        if let result = cleanupResult {
          if result.count == 0 {
            Text("No missing transcript files were found.")
          } else {
            Text("Cleaned up \(result.count) transcript(s) with missing files.")
          }
        }
      }

      // Scope filter
      HStack {
        Text("Type")
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("Type", selection: $selectedScope) {
          Text("Conversations\(countSuffix(.conversations))").tag(InventoryScope.conversations)
          Text("Metadata\(countSuffix(.metadata))").tag(InventoryScope.metadata)
          Text("All\(countSuffix(.all))").tag(InventoryScope.all)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .accessibilityLabel("Transcript type filter")

        Spacer()
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Session list with transcript ID-based selection (FIXED: use filteredSessions)
      List(filteredSessions, id: \.identifier, selection: $selectedTranscriptId) { session in
        sessionRow(session)
          .tag(session.identifier)
          .contextMenu {
            exportContextMenu(for: session)
          }
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
            Image(systemName: "hourglass")
              .font(.caption2)
              .symbolRenderingMode(.monochrome)
              .foregroundStyle(.tertiary)
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

        // v23: Active indicator
        if session.identifier == monitor.activeSession?.identifier {
          Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(.green)
            .help("Active session")
        }

        // v23: Pinned badge
        if isPinned(session) {
          Text("PINNED")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue, in: RoundedRectangle(cornerRadius: 4))
            .help("This session is pinned for monitoring")
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
          .help(absoluteTimestamp(session.lastActivity))

        // Metadata-only indicator (always show for transcripts with no entries)
        if session.entryCount == 0 {
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

  // MARK: - Context Menu

  @ViewBuilder
  private func exportContextMenu(for session: TranscriptSession) -> some View {
    // Show export option based on current provider
    switch session.provider {
    case .claudeCode:
      Button {
        exportToCodex(session)
      } label: {
        Label("Export to Codex CLI", systemImage: "arrow.right.doc.on.clipboard")
      }

    case .codexCLI:
      Button {
        exportToClaudeCode(session)
      } label: {
        Label("Export to Claude Code", systemImage: "arrow.right.doc.on.clipboard")
      }

    case .other:
      // No conversion supported for unknown formats
      EmptyView()
    }

    Divider()

    Button {
      NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
    } label: {
      Label("Reveal in Finder", systemImage: "folder")
    }

    Button {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(session.fileURL.path, forType: .string)
    } label: {
      Label("Copy Path", systemImage: "doc.on.doc")
    }

    Divider()

    Button(role: .destructive) {
      transcriptToDelete = session
      showingDeleteConfirmation = true
    } label: {
      Label("Delete Transcript", systemImage: "trash")
    }
  }

  private func exportToCodex(_ session: TranscriptSession) {
    Task {
      await performExport(session: session, to: .codexCLI)
    }
  }

  private func exportToClaudeCode(_ session: TranscriptSession) {
    Task {
      await performExport(session: session, to: .claudeCode)
    }
  }

  private func deleteTranscript(_ session: TranscriptSession) {
    Task {
      do {
        // Delete from database (cascading will remove all related data)
        try monitor.orchestrator.deleteTranscript(transcriptId: session.identifier)

        // Refresh session list
        await monitor.loadAllSessionsFromDatabase()

        // Clear selection if deleted session was selected
        if selectedTranscriptId == session.identifier {
          selectedTranscriptId = nil
        }

        log.info("Deleted transcript: \(session.identifier)")
      } catch {
        log.error("Failed to delete transcript: \(error.localizedDescription)")
      }

      transcriptToDelete = nil
    }
  }

  private func performCleanup() {
    Task {
      do {
        // Clean up missing transcripts
        let deletedIds = try monitor.orchestrator.cleanupMissingTranscripts()

        // Refresh session list
        await monitor.loadAllSessionsFromDatabase()

        // Clear selection if deleted session was selected
        if let selectedId = selectedTranscriptId, deletedIds.contains(selectedId) {
          selectedTranscriptId = nil
        }

        // Show result
        cleanupResult = (count: deletedIds.count, ids: deletedIds)
        showingCleanupAlert = true

        log.info("Cleanup complete: \(deletedIds.count) transcripts removed")
      } catch {
        log.error("Failed to perform cleanup: \(error.localizedDescription)")
      }
    }
  }

  @MainActor
  private func performExport(session: TranscriptSession, to targetFormat: TranscriptFormat) async {
    // Show save panel
    let savePanel = NSSavePanel()
    savePanel.canCreateDirectories = true
    savePanel.showsTagField = false
    savePanel.level = .modalPanel

    // Auto-generate filename based on target format
    let suggestedFilename: String
    let suggestedDirectory: URL?

    let homeDir = FileManager.default.homeDirectoryForCurrentUser

    switch targetFormat {
    case .codexCLI:
      // Codex format: rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
      let timestamp = formatter.string(from: Date())
      let sessionId = session.identifier
      suggestedFilename = "rollout-\(timestamp)-\(sessionId).jsonl"

      // Suggest ~/.codex/sessions/YYYY/MM/DD/
      let calendar = Calendar.current
      let now = Date()
      let year = calendar.component(.year, from: now)
      let month = calendar.component(.month, from: now)
      let day = calendar.component(.day, from: now)

      suggestedDirectory = homeDir
        .appendingPathComponent(".codex")
        .appendingPathComponent("sessions")
        .appendingPathComponent(String(year))
        .appendingPathComponent(String(format: "%02d", month))
        .appendingPathComponent(String(format: "%02d", day))

      // Create directory if it doesn't exist
      try? FileManager.default.createDirectory(at: suggestedDirectory!, withIntermediateDirectories: true)

    case .claudeCode:
      // Claude Code format: <uuid>.jsonl
      suggestedFilename = "\(session.identifier).jsonl"

      // Suggest ~/.claude/projects/<project-path>/
      if let projectRoot = hudViewModel.projectRootURL {
        let projectPathEncoded = projectRoot.path.replacingOccurrences(of: "/", with: "-")
        suggestedDirectory = homeDir
          .appendingPathComponent(".claude")
          .appendingPathComponent("projects")
          .appendingPathComponent(projectPathEncoded)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: suggestedDirectory!, withIntermediateDirectories: true)
      } else {
        suggestedDirectory = nil
      }
    }

    savePanel.nameFieldStringValue = suggestedFilename
    if let dir = suggestedDirectory {
      savePanel.directoryURL = dir
    }

    let response = await savePanel.beginSheetModal(for: NSApp.keyWindow!)

    guard response == .OK, let outputURL = savePanel.url else {
      return
    }

    // Perform conversion
    let sourceFormat: TranscriptFormat = (session.provider == .claudeCode) ? .claudeCode : .codexCLI

    do {
      showToast("Converting transcript...")

      let converter = TranscriptConverter(verbose: false)
      let result = try await converter.convert(
        from: sourceFormat,
        to: targetFormat,
        inputPath: session.fileURL,
        outputPath: outputURL
      )

      // Show success with resume instructions
      await showResumeInstructions(result: result, targetFormat: targetFormat)

      showToast("Exported to \(result.actualOutputPath.lastPathComponent)")

    } catch {
      log.error("Conversion failed: \(error.localizedDescription)")
      showToast("Export failed: \(error.localizedDescription)")
    }
  }

  @MainActor
  private func showResumeInstructions(result: ConversionResult, targetFormat: TranscriptFormat) async {
    let alert = NSAlert()
    alert.messageText = "Transcript Exported"
    alert.alertStyle = .informational

    let instructions: String
    switch targetFormat {
    case .codexCLI:
      if let projectDir = result.projectDir, let sessionId = result.sessionId {
        instructions = """
        To resume in Codex CLI, run:

        cd \(projectDir) && codex resume \(sessionId)

        Or use the picker:
        cd \(projectDir) && codex resume

        📍 Transcript: \(result.actualOutputPath.path)
        """
      } else {
        instructions = """
        📍 Transcript: \(result.actualOutputPath.path)

        Use `codex resume` to continue the conversation.
        """
      }

    case .claudeCode:
      if let projectDir = result.projectDir, let sessionId = result.sessionId {
        instructions = """
        To resume in Claude Code, run:

        cd \(projectDir) && claude --resume \(sessionId)

        📍 Transcript: \(result.actualOutputPath.path)
        """
      } else {
        instructions = """
        📍 Transcript: \(result.actualOutputPath.path)

        Use `claude --resume` to continue the conversation.
        """
      }
    }

    alert.informativeText = instructions

    alert.addButton(withTitle: "Copy Command")
    alert.addButton(withTitle: "OK")

    let response = await alert.beginSheetModal(for: NSApp.keyWindow!)

    if response == .alertFirstButtonReturn {
      // Copy command to clipboard
      if let projectDir = result.projectDir, let sessionId = result.sessionId {
        let command: String
        switch targetFormat {
        case .codexCLI:
          command = "cd \(projectDir) && codex resume \(sessionId)"
        case .claudeCode:
          command = "cd \(projectDir) && claude --resume \(sessionId)"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
      }
    }
  }

  // MARK: - Toast Helper

  private func showToast(_ message: String, duration: TimeInterval = 2.0) {
    NotificationCenter.default.post(
      name: .contextifyShowToast,
      object: nil,
      userInfo: [
        ToastPayloadKey.message: message,
        ToastPayloadKey.duration: duration
      ]
    )
  }

  // MARK: - Helpers

  private func updateCounts() {
    let all = monitor.allSessions
    let newCounts = (
      conversations: all.filter { $0.entryCount > 0 }.count,
      metadata: all.filter { $0.entryCount == 0 }.count,
      all: all.count
    )
    if scopeCounts.conversations != newCounts.conversations ||
       scopeCounts.metadata != newCounts.metadata ||
       scopeCounts.all != newCounts.all {
      scopeCounts = newCounts
    }
  }

  private var filteredSessions: [TranscriptSession] {
    var sessions = monitor.allSessions

    // Apply scope filter FIRST
    switch selectedScope {
    case .conversations:
      sessions = sessions.filter { $0.entryCount > 0 }
    case .metadata:
      sessions = sessions.filter { $0.entryCount == 0 }
    case .all:
      break // No filter
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

  private func absoluteTimestamp(_ date: Date) -> String {
    // Format: "2:34:15 PM, Tuesday, January 15, 2025"
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm:ss a, EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
  }

  // v23 (P0-4): Check if session is pinned in manual follow mode
  private func isPinned(_ session: TranscriptSession) -> Bool {
    guard let pinned = monitor.pinnedKey else { return false }
    return pinned.sessionId == session.identifier && pinned.provider == session.provider
  }

  private func countSuffix(_ scope: InventoryScope) -> String {
    let count: Int
    switch scope {
    case .conversations: count = scopeCounts.conversations
    case .metadata: count = scopeCounts.metadata
    case .all: count = scopeCounts.all
    }
    return count > 0 ? " (\(count))" : ""
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
      log.debug("Cannot persist sessions: coordinator context not yet available (normal during startup)")
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
          // T2: Convert TimelineSourceContext.Provider → DiscoveredProject.Provider via rawValue
          // Use `.other` as the safe fallback to avoid mislabeling unknown providers
          provider: DiscoveredProject.Provider(rawValue: session.provider.rawValue) ?? .other,
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
  @Environment(ConversationMonitor.self) private var monitor  // v23: for pin/unpin actions

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

          // v23: Active pill
          if isActive {
            Label("Active", systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color.green)
              .clipShape(Capsule())
          }

          // v23: Follow actions
          if !isActive {
            Button("Select for Monitoring") {
              onSelect()
            }
            .buttonStyle(.borderedProminent)
          } else {
            // Active session - show pin/unpin based on mode
            // Simplified: just show pin/unpin toggle
            // Full implementation would check followMode from monitor
            Button(action: {
              Task {
                await monitor.unpinToAuto()
              }
            }) {
              Label("Unpin (Auto)", systemImage: "pin.slash")
            }
            .buttonStyle(.bordered)
            .help("Switch to automatic follow mode")
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
  @State static var scope: InventoryScope = .conversations
  @State static var counts: (conversations: Int, metadata: Int, all: Int) = (10, 5, 15)

  static var previews: some View {
    TranscriptInventoryView(
      selectedScope: .constant(.conversations),
      scopeCounts: .constant((conversations: 10, metadata: 5, all: 15)),
      onSelectSession: { _ in }
    )
    .environment(ConversationMonitor.shared)
  }
}
#endif
