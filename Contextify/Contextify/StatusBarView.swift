//
//  StatusBarView.swift
//  Contextify
//
//  SwiftUI component that renders the status bar footer with Apple Intelligence
//  availability indicator and LLM processing queue status
//

import SwiftUI
import Combine
import OSLog
import ContextifyCore

struct StatusBarView: View {
    private let log = Logger(subsystem: "dev.contextify", category: "StatusBarView")
    @Environment(ConversationMonitor.self) private var timeline
    @EnvironmentObject private var folderAccessController: FolderAccessController
    @State private var viewModel: StatusBarViewModel?
    @State private var lastSeenGenerator: ObjectIdentifier?

    // Permission state (App Store builds only)
    @State private var hasCLIAccess: Bool = true  // Assume true until checked

    // Info popover state
    @State private var showAIInfo = false
    @State private var showErrorInfo = false
    @State private var showPermissionInfo = false

    // Animation triggers
    @State private var lastErrorCount = 0
    @State private var errorBounceAnimation = false

    // Cloud sync status
    @State private var cloudSyncManager = CloudSyncManager.shared
    @State private var showCloudSyncInfo = false
    @State private var showCloudSyncDetail = false
    @State private var cloudStatusNow: Date = .now
    private let cloudStatusTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 16) {
            // Permission warning (App Store builds without CLI access)
            if Sandbox.isSandboxed && !hasCLIAccess {
                permissionWarningIndicator

                Divider()
                    .frame(height: 12)
            }

            // Apple Intelligence indicator
            aiStatusIndicator

            // Hide queue status in lite mode (no LLM processing happening)
            if !isLiteModeActive() {
                Divider()
                    .frame(height: 12)

                // Queue status
                queueStatusView
            }

            if shouldShowCloudSync {
                Divider()
                    .frame(height: 12)

                cloudSyncStatusView
            }

            if let ingestMessage = viewModel?.backgroundIngestMessage {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .symbolEffect(.pulse.byLayer, options: .repeating, isActive: true)

                    Text(ingestMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale))
            }

            // Hoover status (if active)
            if let message = viewModel?.hooverMessage {
                Divider()
                    .frame(height: 12)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity.combined(with: .scale))
            }

            Spacer()  // Push content to left
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 0)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .animation(.easeInOut(duration: 0.3), value: viewModel?.hooverMessage)
        .onAppear {
            updateViewModel()
            checkCLIPermissions()
            Task { await cloudSyncManager.refreshStatusFromServer() }
        }
        .onDisappear {
            viewModel?.stop()
        }
        .task(id: generatorIdentity) {
            // Automatically recreate ViewModel when generator changes
            updateViewModel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .permissionAuthorizationDidChange)) { _ in
            // Re-check permissions when user grants access
            checkCLIPermissions()
        }
        .onReceive(cloudStatusTimer) { tick in
            cloudStatusNow = tick
            Task { await cloudSyncManager.refreshStatusFromServer() }
        }
        .onChange(of: viewModel?.recentErrorCount) { _, newCount in
            // Trigger bounce animation on new errors
            if let newCount, newCount > lastErrorCount {
                errorBounceAnimation.toggle()
            }
            lastErrorCount = newCount ?? 0
        }
        .contentTransition(.opacity)  // Smooth state transitions
    }

    /// Compute stable identity for generator to detect changes
    private var generatorIdentity: ObjectIdentifier? {
        timeline.cacheMissGenerator.map { ObjectIdentifier($0) }
    }

    private func updateViewModel() {
        let currentGeneratorId = generatorIdentity

        // Skip if same generator (avoid unnecessary recreation)
        if let lastSeenGenerator, lastSeenGenerator == currentGeneratorId {
            return
        }
        lastSeenGenerator = currentGeneratorId

        // Stop old view model if it exists
        viewModel?.stop()

        // Collect all available providers
        var providers: [any QueueStatsProvider] = []
        if let generator = timeline.cacheMissGenerator {
            providers.append(generator)
        }
        // Add metadata orchestrator (always available as singleton)
        providers.append(TranscriptMetadataOrchestrator.shared)

        // Create new view model with all providers
        let newViewModel = StatusBarViewModel(queueProviders: providers)

        // Load cached AI status BEFORE assigning to viewModel to avoid flicker
        Task { @MainActor in
            await newViewModel.loadCachedAIStatusSync()
            viewModel = newViewModel  // Assign after cache is loaded
            newViewModel.start()
        }
    }

    /// Check if at least one CLI permission is granted (App Store builds only)
    private func checkCLIPermissions() {
        guard Sandbox.isSandboxed else {
            hasCLIAccess = true  // DMG builds always have access
            log.debug("[STATUS-BAR-PERMISSIONS] DMG build - skipping permission check (always has access)")
            return
        }

        Task { @MainActor in
            let claudeAuth = await folderAccessController.authorization(for: .claude)
            let codexAuth = await folderAccessController.authorization(for: .codex)

            let claudeGranted = claudeAuth?.status == .authorized
            let codexGranted = codexAuth?.status == .authorized
            let hasAccess = claudeGranted || codexGranted

            log.info("[STATUS-BAR-PERMISSIONS] Claude=\(claudeGranted, privacy: .public), Codex=\(codexGranted, privacy: .public), hasCLIAccess=\(hasAccess, privacy: .public)")

            hasCLIAccess = hasAccess
        }
    }

    /// Open Settings window with Permissions tab selected
    private func openPermissionsSettings() {
        log.info("[STATUS-BAR-PERMISSIONS] Opening Settings > Permissions tab")

        // Set tab override to trigger permissions tab selection
        ContextifyDefaults.shared.set("permissions", forKey: "Contextify.Settings.SelectedTabOverride")

        // Open Settings window via the handler that properly promotes the app
        StatusItemController.shared.openSettingsHandler?()

        // Clear override after a short delay (so it doesn't persist)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ContextifyDefaults.shared.removeObject(forKey: "Contextify.Settings.SelectedTabOverride")
        }
    }

    // MARK: - Permission Warning Indicator

    @ViewBuilder
    private var permissionWarningIndicator: some View {
        Button(action: openPermissionsSettings) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    // Use Contextify Yellow for warnings
                    .foregroundStyle(Color(red: 0.831, green: 0.659, blue: 0.306))  // #D4A84E
                    .font(.caption)

                Text("No CLI Access")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                InfoButton(isPresented: $showPermissionInfo)
                    .popover(isPresented: $showPermissionInfo) {
                        InfoPopoverContent(
                            title: "Transcript Access Required",
                            message: """
                            Contextify needs access to CLI transcript folders to monitor your Claude Code or Codex sessions.

                            Grant access to at least one:
                            • ~/.claude/projects/ (Claude Code)
                            • ~/.codex/sessions/ (Codex CLI)

                            Click "Grant Access" to open Settings.
                            """,
                            actionLabel: "Grant Access",
                            action: openPermissionsSettings
                        )
                    }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .help("Click to grant transcript folder access")
        .accessibilityLabel("No CLI access granted. Click to open permissions settings.")
    }

    // MARK: - Apple Intelligence Indicator

    @ViewBuilder
    private var aiStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(aiStatusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)  // Label on parent

            Text(aiStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Info button for detailed help
            InfoButton(isPresented: $showAIInfo)
                .popover(isPresented: $showAIInfo) {
                    InfoPopoverContent(
                        title: aiInfoTitle,
                        message: aiInfoMessage,
                        actionLabel: aiInfoActionLabel,
                        action: aiInfoAction
                    )
                }
        }
        .frame(minHeight: 44)  // Tappable for accessibility
        .help(aiStatusTooltip)
        .accessibilityLabel(aiStatusAccessibilityLabel)
    }

    private var aiStatusColor: Color {
        guard let viewModel else { return .secondary }
        switch viewModel.aiStatus {
        case .checking:
            return .secondary
        case .available:
            // Use Contextify Green from color scheme
            return Color(red: 0.318, green: 0.659, blue: 0.420)  // #51A86B
        case .unavailable:
            return .secondary
        case .error:
            // Use Contextify Red from color scheme
            return Color(red: 0.780, green: 0.306, blue: 0.306)  // #C74E4E
        }
    }

    private var aiStatusText: String {
        guard let viewModel else { return "AI Unavailable" }
        switch viewModel.aiStatus {
        case .checking: return "Checking AI..."
        case .available: return "Apple Intelligence"
        case .unavailable(let reason): return reason  // Shows "Lite Mode" in lite mode
        case .error: return "AI Error"
        }
    }

    private var aiStatusTooltip: String {
        guard let viewModel else { return "Initializing" }
        switch viewModel.aiStatus {
        case .checking: return "Checking Apple Intelligence availability..."
        case .available: return "Apple Intelligence"
        case .unavailable: return "Lite Mode: \(LLMAvailability.current.reasonText)"
        case .error: return "AI Error - click (i) for details"
        }
    }

    private var aiStatusAccessibilityLabel: String {
        guard let viewModel else { return "Initializing" }
        switch viewModel.aiStatus {
        case .checking:
            return "Checking Apple Intelligence availability"
        case .available:
            return "Apple Intelligence available"
        case .unavailable(let reason):
            return "Apple Intelligence unavailable: \(reason)"
        case .error(let message):
            return "Apple Intelligence error: \(message)"
        }
    }

    // MARK: - Queue Status

    @ViewBuilder
    private var queueStatusView: some View {
        if viewModel == nil || !viewModel!.monitoringActive {
            // Not monitoring state (generator is nil)
            HStack(spacing: 4) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Not monitoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Start a project to enable timeline monitoring")
            .accessibilityLabel("Timeline monitoring inactive")

        } else if let viewModel, viewModel.recentErrorCount > 0 {
            // Error state
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    // Use Contextify Yellow for warnings
                    .foregroundStyle(Color(red: 0.831, green: 0.659, blue: 0.306))  // #D4A84E
                    .font(.caption)
                    .symbolEffect(.bounce, value: errorBounceAnimation)

                Text("\(viewModel.recentErrorCount) error\(viewModel.recentErrorCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Info button for detailed error help
                InfoButton(isPresented: $showErrorInfo)
                    .popover(isPresented: $showErrorInfo) {
                        InfoPopoverContent(
                            title: "LLM Generation Errors",
                            message: errorInfoMessage,
                            actionLabel: "Check System Settings",
                            action: openSystemSettings
                        )
                    }
            }
            .help("LLM generation errors occurred")  // Simplified tooltip
            .accessibilityLabel("\(viewModel.recentErrorCount) generation errors")

        } else if let viewModel, viewModel.queueDepth > 0 {
            // Processing state - show spinner whenever queue has items
            // (queue is considered "processing" even during brief idle periods between items)
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)

                if viewModel.queueDepth > 100 {
                    Text("Processing many items...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Processing \(viewModel.queueDepth) \(viewModel.queueDepth == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.estimatedSecondsRemaining > 0 {
                        Text("(~\(viewModel.estimatedSecondsRemaining)s)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .accessibilityLabel("Processing \(viewModel.queueDepth) summaries, estimated \(viewModel.estimatedSecondsRemaining) seconds remaining")

        } else {
            // Up to date (queue empty AND no recent errors)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    // Use Contextify Green for success
                    .foregroundStyle(Color(red: 0.318, green: 0.659, blue: 0.420))  // #51A86B
                    .font(.caption)

                Text("Up to date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("All summaries up to date")
        }
    }

    // MARK: - Info Popover Content

    /// Title for AI status info popover
    private var aiInfoTitle: String {
        guard let viewModel else { return "Apple Intelligence" }
        switch viewModel.aiStatus {
        case .unavailable:
            return "Lite Mode"
        default:
            return "Apple Intelligence"
        }
    }

    /// Detailed message for AI status info popover
    private var aiInfoMessage: String {
        guard let viewModel else { return "Initializing..." }
        switch viewModel.aiStatus {
        case .checking:
            return """
            Checking Apple Intelligence availability...

            This typically takes a few seconds during app startup.
            """
        case .available:
            return """
            Apple Intelligence is available and generating conversation summaries using on-device language models (FoundationLLM).

            Summaries are generated with no network latency or additional API costs.
            """
        case .unavailable:
            return """
            AI-generated summaries and drag-and-drop re-ordering of projects are both disabled.

            Local AI summaries require Apple Intelligence (Tahoe + Apple Silicon).
            """
        case .error(let message):
            return """
            Apple Intelligence encountered an error.

            Error: \(message)

            Try these steps:
            1. Check that Apple Intelligence is enabled in System Settings
            2. Restart Contextify
            3. Restart your Mac if the issue persists

            Errors auto-clear after 3 successful generations.
            """
        }
    }

    /// Action button label for AI status popover (nil if no action needed)
    private var aiInfoActionLabel: String? {
        guard let viewModel else { return nil }
        if case .error = viewModel.aiStatus {
            return "Open System Settings"
        }
        return nil
    }

    /// Action for AI status popover button
    private var aiInfoAction: (() -> Void)? {
        guard let viewModel else { return nil }
        if case .error = viewModel.aiStatus {
            return openSystemSettings
        }
        return nil
    }

    /// Detailed message for error info popover
    private var errorInfoMessage: String {
        guard let viewModel else { return "" }
        let count = viewModel.recentErrorCount
        let reason = viewModel.topErrorReason

        var message = """
        \(count) conversation \(count == 1 ? "entry" : "entries") failed to generate summaries.
        """

        if let reason {
            message += "\n\nTop error: \(simplifyErrorReason(reason))"
            message += "\n\n" + contextualGuidance(for: reason)
        }

        message += """


        How Contextify handles errors:
        • Failed entries won't be retried automatically
        • Errors auto-clear after 3 successful generations
        • Summaries are optional - entries remain accessible
        """

        return message
    }

    /// Provide contextual guidance based on error type
    private func contextualGuidance(for reason: String) -> String {
        // llmUnavailable - "Apple Intelligence is overloaded and not responding"
        if reason.contains("overload") || reason.contains("not responding") {
            return """
            What this means:
            Apple Intelligence is temporarily overloaded. This is usually transient and should resolve within 1-2 minutes.

            What to do:
            Wait a moment and the system will recover automatically. No action needed.
            """
        }

        // decodingFailure - "Summary format was invalid: Failed to extract content"
        if reason.contains("format was invalid") || reason.contains("Failed to extract") {
            return """
            What this means:
            The AI generated a response in an unexpected format that couldn't be parsed.

            What to do:
            This is a rare parsing issue. The entry remains accessible without a summary. No action needed.
            """
        }

        // contextOverflow - "Message too long"
        if reason.contains("too long") || reason.contains("tokens") {
            return """
            What this means:
            This conversation entry exceeded the maximum size for summary generation.

            What to do:
            The entry is too large to summarize but remains fully accessible in the timeline. No action needed.
            """
        }

        // guardrailViolation - safety filters
        if reason.contains("safety filters") || reason.contains("grounding") || reason.contains("REJECTED") {
            return """
            What this means:
            Apple Intelligence's safety filters prevented summary generation for this content.

            What to do:
            The entry remains accessible without a summary. No action needed.
            """
        }

        // llmTimeout
        if reason.contains("timeout") || reason.contains("timed out") {
            return """
            What this means:
            Summary generation took too long and was cancelled.

            What to do:
            This is usually temporary. The entry remains accessible without a summary.
            """
        }

        // databaseError
        if reason.contains("database error") {
            return """
            What this means:
            A database error occurred while saving the summary.

            What to do:
            Check available disk space. If the issue persists, check application logs.
            """
        }

        // Generic/unexpected
        return """
        What to do:
        The entry remains accessible without a summary. If this persists, check application logs for details.
        """
    }

    // MARK: - Helper Functions

    /// Simplify technical error messages for user display
    private func simplifyErrorReason(_ reason: String) -> String {
        if reason.contains("REJECTED") {
            return "Summary quality too low"
        } else if reason.contains("grounding") {
            return "Content not grounded in source"
        } else if reason.contains("leaked") {
            return "Summary was invalid"
        } else if reason.contains("confidence") {
            return "Low confidence result"
        } else if reason.contains("timeout") {
            return "Generation timed out"
        } else {
            return reason  // Return as-is if no simplification
        }
    }

    /// Open System Settings (Apple Intelligence or Security & Privacy)
    private func openSystemSettings() {
        // Try to open Apple Intelligence settings first (macOS 15+)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Previews
// Note: Previews disabled as StatusBarView now requires ConversationMonitor environment

private extension StatusBarView {
    enum CloudSyncDisplayState {
        case upToDate
        case syncing
        case stalled
        case offline
        case needsAttention
        case error
        case disabled
    }

    var shouldShowCloudSync: Bool {
        cloudSyncManager.syncState != .disabled
            || cloudSyncManager.cloudStatus != nil
            || cloudSyncManager.cloudStatusError != nil
    }

    var cloudActiveSession: CloudActivePushSessionStatus? {
        cloudSyncManager.cloudStatus?.activePushSession
    }

    /// Returns the server's active push session only when it belongs to this
    /// client's current connection. Returns nil for orphaned sessions.
    var visibleCloudActiveSession: CloudActivePushSessionStatus? {
        guard let session = cloudActiveSession, !cloudSyncManager.isActiveSessionOrphaned else {
            return nil
        }
        return session
    }

    var cloudDisplayState: CloudSyncDisplayState {
        if cloudSyncManager.syncState == .disabled { return .disabled }
        if cloudSyncManager.cloudOffline { return .offline }

        // Skip server-side session state when the session is orphaned
        // (from a previous connection, not this client's current session).
        if let session = visibleCloudActiveSession {
            let phase = session.phase.lowercased()
            let completion = session.completionState?.lowercased()
            let attention = session.needsAttentionCount ?? 0

            if phase == "stalled" { return .stalled }
            if completion == "blocked" || completion == "completed_with_issues" || attention > 0 {
                return .needsAttention
            }
            if cloudSyncManager.syncState == .syncing || completion == "in_progress" {
                return .syncing
            }
        }

        if cloudSyncManager.syncState == .syncing { return .syncing }
        if case .error = cloudSyncManager.syncState { return .error }
        return .upToDate
    }

    @ViewBuilder
    var cloudSyncStatusView: some View {
        Button {
            showCloudSyncInfo = true
        } label: {
            HStack(spacing: 6) {
                if cloudDisplayState == .syncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: cloudChipIconName)
                        .foregroundStyle(cloudChipColor)
                        .font(.caption)
                }

                Text(cloudChipText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(cloudChipTooltip)
        .accessibilityLabel(cloudChipText)
        .popover(isPresented: $showCloudSyncInfo) {
            cloudSyncPopoverContent
        }
        .sheet(isPresented: $showCloudSyncDetail) {
            CloudSyncDetailSheet(syncManager: cloudSyncManager, now: cloudStatusNow)
        }
    }

    @ViewBuilder
    var cloudSyncPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cloud Sync")
                    .font(.headline)
                Spacer()
                Button {
                    openCloudSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle().inset(by: -8))
                .accessibilityLabel("Open Cloud Settings")
                .help("Open Cloud Settings")
            }

            HStack(spacing: 6) {
                Image(systemName: cloudChipIconName)
                    .foregroundStyle(cloudChipColor)
                    .font(.subheadline)
                Text(cloudChipText)
                    .font(.subheadline)
            }

            if let session = visibleCloudActiveSession,
               let total = session.entriesTotal, total > 0 {
                let resolved = min(max(session.entriesResolved ?? 0, 0), total)
                ProgressView(value: Double(resolved), total: Double(total))
                    .progressViewStyle(.linear)

                Text("\(formatCount(resolved)) / \(formatCount(total)) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let displayEta = cloudSyncManager.cloudSmoothedEtaSeconds ?? session.etaSeconds
                let displayThroughput = cloudSyncManager.cloudSmoothedThroughputEntriesPerMin ?? session.throughputEntriesPerMin

                if let eta = displayEta, eta > 0 {
                    Text("ETA: (etaLabel(seconds: eta))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let throughput = displayThroughput, throughput > 0 {
                    Text("Throughput: (formatCount(Int(throughput.rounded()))) entries/min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let attention = session.needsAttentionCount, attention > 0 {
                    Text("Needs attention: \(formatCount(attention))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let error = cloudSyncManager.cloudStatusError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    cloudSyncManager.triggerSync()
                    Task { await cloudSyncManager.refreshStatusFromServer() }
                } label: {
                    Label(cloudPrimaryActionLabel, systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)

                Button {
                    openCloudDashboard()
                } label: {
                    Label("View Details", systemImage: "globe")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 340, alignment: .leading)
        .animation(nil, value: cloudChipText)
    }

    var cloudChipIconName: String {
        switch cloudDisplayState {
        case .upToDate:
            return "checkmark.circle.fill"
        case .stalled:
            return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .offline:
            return "wifi.slash"
        case .needsAttention:
            return "exclamationmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .disabled:
            return "cloud.slash"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        }
    }

    var cloudChipColor: Color {
        switch cloudDisplayState {
        case .upToDate:
            return Color(red: 0.318, green: 0.659, blue: 0.420)
        case .syncing:
            return .secondary
        case .stalled, .offline, .needsAttention:
            return Color(red: 0.831, green: 0.659, blue: 0.306)
        case .error:
            return Color(red: 0.780, green: 0.306, blue: 0.306)
        case .disabled:
            return .secondary
        }
    }

    var cloudChipText: String {
        switch cloudDisplayState {
        case .upToDate:
            return "Cloud up to date"
        case .syncing:
            if let session = visibleCloudActiveSession,
               let total = session.entriesTotal,
               let resolved = session.entriesResolved,
               total > 0 {
                let percent = Int((Double(min(max(resolved, 0), total)) / Double(total) * 100).rounded())
                return "Syncing \(percent)%"
            }
            return "Syncing"
        case .stalled:
            return "Sync stalled"
        case .offline:
            return "Cloud offline"
        case .needsAttention:
            return "Sync needs attention"
        case .error:
            return "Cloud sync error"
        case .disabled:
            return "Cloud disabled"
        }
    }

    var cloudChipTooltip: String {
        switch cloudDisplayState {
        case .upToDate:
            return "Cloud sync is up to date"
        case .syncing:
            return "Cloud sync in progress"
        case .stalled:
            return "Cloud sync appears stalled"
        case .offline:
            return "Offline: changes are saved locally and queued for upload"
        case .needsAttention:
            return "Cloud sync completed with issues that need attention"
        case .error:
            return "Cloud sync error"
        case .disabled:
            return "Cloud sync is disabled"
        }
    }

    var cloudPrimaryActionLabel: String {
        switch cloudDisplayState {
        case .offline, .stalled, .error, .needsAttention:
            return "Retry now"
        default:
            return "Sync now"
        }
    }

    func etaLabel(seconds: Int) -> String {
        if seconds < 60 { return "under a minute" }
        let minutes = Int(round(Double(seconds) / 60.0))
        if minutes < 60 { return "~\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "~\(hours) hr" : "~\(hours) hr \(rem) min"
    }

    func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    func openCloudDashboard() {
        guard let base = cloudSyncManager.configuredServerURL,
              var components = URLComponents(string: base) else { return }
        components.path = "/cloud/sync"
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    func openCloudSettings() {
        ContextifyDefaults.shared.set("cloud", forKey: "Contextify.Settings.SelectedTabOverride")
        StatusItemController.shared.openSettingsHandler?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            ContextifyDefaults.shared.removeObject(forKey: "Contextify.Settings.SelectedTabOverride")
        }
    }
}

private struct CloudSyncDetailSheet: View {
    let syncManager: CloudSyncManager
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cloud Sync Activity")
                .font(.headline)

            if let session = syncManager.cloudStatus?.activePushSession,
               !syncManager.isActiveSessionOrphaned,
               let total = session.entriesTotal, total > 0 {
                let resolved = min(max(session.entriesResolved ?? 0, 0), total)
                ProgressView(value: Double(resolved), total: Double(total))
                    .progressViewStyle(.linear)

                Text("\(resolved) / \(total) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Phase: \(session.phase)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let completion = session.completionState {
                    Text("Outcome: \(completion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let attention = session.needsAttentionCount, attention > 0 {
                    Text("Needs attention: \(attention)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                let displayThroughput = syncManager.cloudSmoothedThroughputEntriesPerMin ?? session.throughputEntriesPerMin
                let displayEta = syncManager.cloudSmoothedEtaSeconds ?? session.etaSeconds

                if let throughput = displayThroughput, throughput > 0 {
                    Text("Throughput: (Int(throughput.rounded())) entries/min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let eta = displayEta, eta > 0 {
                    Text("ETA: (etaLabel(seconds: eta))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active upload session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let push = syncManager.lastPushResult {
                Text("Last upload: \(push.entriesPushed) uploaded, \(push.duplicatesSkipped) already synced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pull = syncManager.lastPullResult {
                Text("Last download: \(pull.entriesImported) imported, \(pull.entriesSkipped) already present")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let refreshed = syncManager.cloudStatusUpdatedAt {
                Text("Status refreshed \(RelativeDateTimeFormatter().localizedString(for: refreshed, relativeTo: now))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 320)
    }

    private func etaLabel(seconds: Int) -> String {
        if seconds < 60 { return "under a minute" }
        let minutes = Int(round(Double(seconds) / 60.0))
        if minutes < 60 { return "~\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "~\(hours) hr" : "~\(hours) hr \(rem) min"
    }
}
