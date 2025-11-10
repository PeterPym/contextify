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

  @State private var selectedTranscriptId: String?  // Changed from URL to transcript ID
  @State private var searchText = ""
  @State private var debouncedSearch = ""  // Debounced search for filtering
  @State private var debounceTask: Task<Void, Never>?
  @State private var metadata: [String: TranscriptMetadata] = [:]  // Changed key from URL to transcript ID
  @State private var loadingMetadata: Set<String> = []  // Changed from URL to transcript ID
  @State private var metadataErrors: [String: String] = [:]  // Track errors by transcript ID (Phase 3)
  @State private var metadataTasks: [String: Task<Void, Never>] = [:]  // Track background tasks for cancellation
  @State private var lastVisibleSessionIDs: Set<String> = []  // Viewport tracking
  @State private var viewportDebounceTask: Task<Void, Never>?  // Debounced viewport handler
  @State private var showingFlushAlert = false
  @State private var lastFlushCount = 0
  @State private var showingDeleteConfirmation = false
  @State private var transcriptToDelete: TranscriptSession?
  @State private var showingCleanupConfirmation = false
  @State private var cleanupResult: (count: Int, ids: [String])? = nil
  @State private var showingCleanupAlert = false
  @AppStorage("transcript.hideBriefSessions") private var hideBriefSessions = true
  @State private var showMetadataInfo: [String: Bool] = [:]  // Track info popover state per session
  @State private var showErrorInfo: [String: Bool] = [:]  // Track error info popover state per session

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

          Menu {
            Toggle("Hide Brief Sessions", isOn: $hideBriefSessions)
            if devMode.isEnabled {
              Divider()
              Button {
                flushHeuristicCache()
              } label: {
                Label("Flush Heuristic Cache", systemImage: "trash")
              }
              Button {
                showingCleanupConfirmation = true
              } label: {
                Label("Clean Up Missing Files", systemImage: "trash.circle")
              }
            }
          } label: {
            Image(systemName: "ellipsis")
              .foregroundStyle(.secondary)
              .padding(6)
              .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
          }
          .menuStyle(.borderlessButton)
          .fixedSize()
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

      // Session list with transcript ID-based selection + viewport tracking
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(filteredSessions, id: \.identifier) { session in
            sessionRow(session)
              .id(session.identifier)
              .contentShape(Rectangle())
              .onTapGesture {
                selectedTranscriptId = session.identifier
              }
              .background(selectedTranscriptId == session.identifier ? Color.accentColor.opacity(0.15) : Color.clear)
              .contextMenu {
                exportContextMenu(for: session)
              }
          }
        }
        .padding(.horizontal, 8)
        .scrollTargetLayout()
      }
      .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.55) { visibleIDs in
        replaceVisibleSnapshot(visibleIDs)
      }
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

        // Ensure discovered sessions are persisted to database (prevents FK errors)
        Task {
          await persistDiscoveredSessions(newSessions)
        }

        // Note: Metadata loading now handled by viewport tracking (handleVisibleSessionsChanged)
        // No hardcoded first-10 load - only generate for what's actually visible
      }
      .task {
        // Ensure sessions are persisted before loading metadata
        await persistDiscoveredSessions(monitor.allSessions)

        // Load cached metadata for all sessions on initial appearance
        // (viewport tracking will handle subsequent updates and generation queue)
        log.info("[META-INIT] Loading cached metadata for \(monitor.allSessions.count) sessions on initial appearance")
        await loadMetadataForSessions(monitor.allSessions)
      }
      .onDisappear {
        // Cancel pending debounce tasks to prevent leaks
        debounceTask?.cancel()
        debounceTask = nil
        viewportDebounceTask?.cancel()
        viewportDebounceTask = nil

        // Cancel all metadata generation tasks
        metadataTasks.values.forEach { $0.cancel() }
        metadataTasks.removeAll()
      }
      .onReceive(NotificationCenter.default.publisher(for: .transcriptMetadataGenerationStarted)) { notification in
        // Metadata generation started - show loading indicator
        guard let transcriptId = notification.userInfo?["transcriptId"] as? String else { return }
        loadingMetadata.insert(transcriptId)
        log.debug("[META-START-UI] Showing loading indicator for \(transcriptId, privacy: .public)")
      }
      .onReceive(NotificationCenter.default.publisher(for: .transcriptMetadataUpdated)) { notification in
        // Metadata generated by orchestrator - fetch from SQL and update UI
        guard let transcriptId = notification.userInfo?["transcriptId"] as? String else { return }
        guard let orchestrator = monitor.orchestrator else { return }

        Task { @MainActor in
          // Clear loading indicator
          loadingMetadata.remove(transcriptId)

          if let record = try? orchestrator.getMetadata(forTranscript: transcriptId) {
            metadata[transcriptId] = record.toUIModel()
            log.debug("[META-UPDATE] Updated UI with generated metadata for \(transcriptId, privacy: .public)")
          }
        }
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
        Image(session.provider.iconImage)
          .renderingMode(.template)
          .foregroundStyle(session.provider.color)
          .frame(width: 16)

        if let meta = metadata[session.identifier] {
          // Show title with confidence indicator for low-confidence metadata
          HStack(spacing: 4) {
            Text(meta.title)
              .font(.callout)
              .lineLimit(1)
            if meta.confidence < 0.5 {
              InfoButton(isPresented: Binding(
                get: { showMetadataInfo[session.identifier] ?? false },
                set: { showMetadataInfo[session.identifier] = $0 }
              ))
              .popover(isPresented: Binding(
                get: { showMetadataInfo[session.identifier] ?? false },
                set: { showMetadataInfo[session.identifier] = $0 }
              )) {
                InfoPopoverContent(
                  title: "Low Confidence Metadata",
                  message: """
                  Title: \(meta.title)

                  Description: \(meta.description)

                  Confidence: \(Int(meta.confidence * 100))%

                  This metadata was generated with low confidence and may not accurately represent the transcript content.
                  """
                )
              }
            }
          }
        } else if let error = metadataErrors[session.identifier] {
          // Show error state with retry option (Phase 3)
          HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
              .font(.caption2)
              .foregroundStyle(.orange)
            Text("Failed to analyze")
              .font(.caption)
              .foregroundStyle(.secondary)
            Button("Retry") {
              retryMetadata(for: session)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.blue)
            InfoButton(isPresented: Binding(
              get: { showErrorInfo[session.identifier] ?? false },
              set: { showErrorInfo[session.identifier] = $0 }
            ))
            .popover(isPresented: Binding(
              get: { showErrorInfo[session.identifier] ?? false },
              set: { showErrorInfo[session.identifier] = $0 }
            )) {
              InfoPopoverContent(
                title: "Metadata Generation Failed",
                message: """
                Error: \(error)

                This transcript could not be analyzed. Common causes:
                • Apple Intelligence is disabled or unavailable
                • Transcript content is corrupted or empty
                • System resources temporarily unavailable

                Try clicking the Retry button to attempt generation again.
                """
              )
            }
          }
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
        Text(session.lastActivity.relativeTimeString)
          .font(.caption)
          .foregroundStyle(.secondary)
          .help(session.lastActivity.absoluteTimestampString)

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
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor))
    )
    .overlay(alignment: .leading) {
      Capsule()
        .fill(Color.secondary.opacity(0.3))
        .frame(width: 3)
        .padding(.vertical, 4)
    }
    .contentShape(Rectangle())
    // Note: Removed .onAppear metadata loading - now using aggregate viewport tracking
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

    Button {
      regenerateMetadata(for: session)
    } label: {
      Label("Regenerate Metadata", systemImage: "arrow.clockwise")
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

    // Single-pass counting to avoid O(2n) filter operations
    var conversationCount = 0
    var metadataCount = 0
    for session in all {
      if session.entryCount > 0 {
        conversationCount += 1
      } else {
        metadataCount += 1
      }
    }

    let newCounts = (
      conversations: conversationCount,
      metadata: metadataCount,
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

    // Apply brief sessions filter
    if hideBriefSessions {
      sessions = sessions.filter { $0.entryCount >= 3 }
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

  // MARK: - Shared Utilities
  // Provider and time formatters now use shared extensions:
  // - provider.displayName (TimelineModels.swift)
  // - provider.iconImage (TimelineModels.swift)
  // - provider.color (TimelineModels.swift)
  // - date.relativeTimeString (SharedExtensions.swift)
  // - date.absoluteTimestampString (SharedExtensions.swift)

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

  // MARK: - Viewport-Aware Metadata Loading

  /// Aggregate snapshot of visible session IDs from onScrollTargetVisibilityChange
  /// Pattern matches ConversationMonitor.replaceVisibleSnapshot() for consistency
  @MainActor
  private func replaceVisibleSnapshot(_ ids: [String]) {
    log.info("[VIEWPORT-CHANGE] Viewport update: \(ids.count, privacy: .public) sessions in viewport")

    let current = Set(ids)
    let newlyVisible = current.subtracting(lastVisibleSessionIDs)
    if !newlyVisible.isEmpty {
      log.info("[VIEWPORT-VISIBLE] \(newlyVisible.count, privacy: .public) newly visible sessions")
      for id in newlyVisible.prefix(5) {  // Log first 5 (matches ConversationMonitor pattern)
        log.info("[VIEWPORT-ENTRY] Now visible: \(id, privacy: .public)")
      }
      if newlyVisible.count > 5 {
        log.info("[VIEWPORT-ENTRY] ... and \(newlyVisible.count - 5, privacy: .public) more newly visible sessions")
      }
    }

    lastVisibleSessionIDs = current

    // Debounce viewport changes to avoid queueing during rapid scrolling (500ms)
    // Matches TranscriptMetadataOrchestrator stabilizationDelayMs
    viewportDebounceTask?.cancel()
    viewportDebounceTask = Task {
      try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms = 0.5 seconds
      guard !Task.isCancelled else { return }

      log.info("[VIEWPORT-SETTLED] Viewport settled on \(lastVisibleSessionIDs.count) visible sessions")

      // Prune metadata queue to visible sessions
      await TranscriptMetadataOrchestrator.shared.pruneQueue(keepOnly: lastVisibleSessionIDs)

      // Load metadata for visible sessions
      await queueVisibleMetadataGeneration(lastVisibleSessionIDs)
    }
  }

  /// Queue metadata generation for visible sessions
  /// Pattern matches ConversationMonitor.queueVisibleGeneratingEntries() naming
  @MainActor
  private func queueVisibleMetadataGeneration(_ visibleIDs: Set<String>) async {
    let visibleSessions = filteredSessions.filter {
      visibleIDs.contains($0.identifier)
    }

    log.debug("[META-QUEUE] Queueing metadata for \(visibleSessions.count) visible sessions")
    await loadMetadataForSessions(visibleSessions)
  }

  /// Retry metadata generation for a failed session (Phase 3)
  @MainActor
  private func retryMetadata(for session: TranscriptSession) {
    let id = session.identifier

    log.info("[META-RETRY] Retrying metadata for session: \(id, privacy: .public)")

    // Clear error state and trigger regeneration
    metadataErrors.removeValue(forKey: id)
    loadingMetadata.insert(id)
    log.debug("[META-RETRY] Cleared error state for session: \(id, privacy: .public)")

    let task = Task { @MainActor in
      defer {
        loadingMetadata.remove(id)
        metadataTasks[id] = nil
      }
      do {
        let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
          for: session,
          forceRegenerate: true  // Force regeneration to retry
        )
        metadata[id] = generated
        metadataErrors.removeValue(forKey: id)
        log.info("[META-DONE] ✅ Retry succeeded for \(id, privacy: .public): \(generated.title, privacy: .public)")
      } catch {
        let errorMessage = error.localizedDescription
        metadataErrors[id] = errorMessage
        log.error("[META-ERROR] ❌ Retry failed for \(id, privacy: .public): \(errorMessage, privacy: .public)")
      }
    }
    metadataTasks[id] = task
  }

  /// Regenerate metadata for a session (context menu action)
  @MainActor
  private func regenerateMetadata(for session: TranscriptSession) {
    let id = session.identifier

    log.info("[META-REGEN] Regenerating metadata for session: \(id, privacy: .public)")

    // Clear existing metadata and trigger forced regeneration
    metadata.removeValue(forKey: id)
    metadataErrors.removeValue(forKey: id)
    loadingMetadata.insert(id)
    log.debug("[META-REGEN] Cleared cached metadata for session: \(id, privacy: .public)")

    let task = Task { @MainActor in
      defer {
        loadingMetadata.remove(id)
        metadataTasks[id] = nil
      }
      do {
        let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
          for: session,
          forceRegenerate: true  // Force regeneration to bypass cache
        )
        metadata[id] = generated
        metadataErrors.removeValue(forKey: id)
        log.info("[META-DONE] ✅ Regeneration succeeded for \(id, privacy: .public): \(generated.title, privacy: .public)")
      } catch {
        let errorMessage = error.localizedDescription
        metadataErrors[id] = errorMessage
        log.error("[META-ERROR] ❌ Regeneration failed for \(id, privacy: .public): \(errorMessage, privacy: .public)")
      }
    }
    metadataTasks[id] = task
  }

  @MainActor
  private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
    // Queue-based loading: batch fetch from SQL, then enqueue cache misses to orchestrator
    guard let orchestrator = monitor.orchestrator else {
      return
    }

    log.debug("[META-BATCH] Loading metadata for \(sessions.count, privacy: .public) sessions")

    // Batch fetch metadata from SQL
    let transcriptIds = sessions.map(\.identifier)
    let cachedMetadata = (try? orchestrator.getMetadataBatch(transcriptIds: transcriptIds)) ?? [:]
    log.debug("[META-BATCH] Found \(cachedMetadata.count, privacy: .public) cached, need to generate \(transcriptIds.count - cachedMetadata.count, privacy: .public)")

    // Update state with cached results
    for (transcriptId, record) in cachedMetadata {
      metadata[transcriptId] = record.toUIModel()
    }

    // Find sessions that need generation (not in cache)
    let missingIds = Set(transcriptIds).subtracting(Set(cachedMetadata.keys))
    let missingSessions = sessions.filter { missingIds.contains($0.identifier) }

    log.info("[META-QUEUE] Enqueueing \(missingSessions.count, privacy: .public) sessions for metadata generation")

    // Enqueue cache misses to orchestrator (replaces concurrent TaskGroup with LIFO queue)
    await TranscriptMetadataOrchestrator.shared.enqueueMetadata(for: missingSessions)
  }
}

// Note: TranscriptDetailView extracted to TranscriptDetailView.swift (Phase 2)
// MARK: - Previews

#if DEBUG
struct TranscriptInventoryView_Previews: PreviewProvider {
  @State static var scope: InventoryScope = .conversations
  @State static var counts: (conversations: Int, metadata: Int, all: Int) = (10, 5, 15)

  static var previews: some View {
    TranscriptInventoryView(
      selectedScope: .constant(.conversations),
      scopeCounts: .constant((conversations: 10, metadata: 5, all: 15))
    )
    .environment(ConversationMonitor.shared)
  }
}
#endif
