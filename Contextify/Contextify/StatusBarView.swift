//
//  StatusBarView.swift
//  Contextify
//
//  SwiftUI component that renders the status bar footer with Apple Intelligence
//  availability indicator and LLM processing queue status
//

import SwiftUI

struct StatusBarView: View {
    @Environment(ConversationMonitor.self) private var timeline
    @State private var viewModel: StatusBarViewModel?
    @State private var lastSeenGenerator: ObjectIdentifier?

    // Info popover state
    @State private var showAIInfo = false
    @State private var showErrorInfo = false

    // Animation triggers
    @State private var lastErrorCount = 0
    @State private var errorBounceAnimation = false

    var body: some View {
        HStack(spacing: 16) {
            // Apple Intelligence indicator
            aiStatusIndicator

            Divider()
                .frame(height: 12)

            // Queue status
            queueStatusView

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
        .padding(.horizontal, 12)
        .padding(.vertical, 4)  // Reduced from 6 to 4
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .animation(.easeInOut(duration: 0.3), value: viewModel?.hooverMessage)
        .onAppear {
            updateViewModel()
        }
        .onDisappear {
            viewModel?.stop()
        }
        .task(id: generatorIdentity) {
            // Automatically recreate ViewModel when generator changes
            updateViewModel()
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
                        title: "Apple Intelligence",
                        message: aiInfoMessage,
                        actionLabel: aiInfoActionLabel,
                        action: aiInfoAction
                    )
                }
        }
        .frame(minHeight: 44)  // Tappable for accessibility
        .help(aiStatusText)  // Simplified tooltip - just the status
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
        case .unavailable: return "AI Unavailable"
        case .error: return "AI Error"
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

        } else if let viewModel, viewModel.isProcessing && viewModel.queueDepth > 0 {
            // Processing state (only show if items exist - prevents race condition display)
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

        } else if let viewModel, viewModel.queueDepth > 0 {
            // Pending (not processing yet)
            Text("\(viewModel.queueDepth) pending")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(viewModel.queueDepth) summaries pending")

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

            Summaries are generated locally with no network latency or additional API costs.
            """
        case .unavailable(let reason):
            return """
            Apple Intelligence is unavailable.

            Reason: \(reason)

            Summaries will be generated using fallback heuristics (less detailed).
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
