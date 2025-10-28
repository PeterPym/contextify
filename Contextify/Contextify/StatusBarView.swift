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
        viewModel = newViewModel
        newViewModel.start()
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
        }
        .frame(minWidth: 44, minHeight: 44)  // Tappable for accessibility
        .help(aiStatusTooltip)
        .accessibilityLabel(aiStatusAccessibilityLabel)
    }

    private var aiStatusColor: Color {
        guard let viewModel else { return .secondary }
        switch viewModel.aiStatus {
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
        case .available: return "Apple Intelligence"
        case .unavailable: return "AI Unavailable"
        case .error: return "AI Error"
        }
    }

    private var aiStatusTooltip: String {
        guard let viewModel else { return "Initializing..." }
        switch viewModel.aiStatus {
        case .available:
            return "Apple Intelligence is available\nUsing FoundationLLM for on-device summaries"
        case .unavailable(let reason):
            return "Apple Intelligence unavailable\n\(reason)"
        case .error(let message):
            return "Apple Intelligence error\n\(message)\n\nTry toggling AI in System Settings, then restart."
        }
    }

    private var aiStatusAccessibilityLabel: String {
        guard let viewModel else { return "Initializing" }
        switch viewModel.aiStatus {
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

                Text("\(viewModel.recentErrorCount) error\(viewModel.recentErrorCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(errorTooltip(count: viewModel.recentErrorCount, reason: viewModel.topErrorReason))
            .accessibilityLabel("\(viewModel.recentErrorCount) generation errors")

        } else if let viewModel, viewModel.isProcessing && viewModel.queueDepth > 0 {
            // Processing state (only show if items exist - prevents race condition display)
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)

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

    // MARK: - Helper Functions

    /// Generate actionable error tooltip
    private func errorTooltip(count: Int, reason: String?) -> String {
        var message = "LLM generation failed for \(count) \(count == 1 ? "entry" : "entries")"

        if let reason = reason {
            // Simplify technical error messages
            let simplified = simplifyErrorReason(reason)
            message += "\n\nReason: \(simplified)"
        }

        message += "\n\nErrors auto-clear after 3 successful generations."
        message += "\nIf errors persist, check Apple Intelligence in System Settings."

        return message
    }

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
}

// MARK: - Previews
// Note: Previews disabled as StatusBarView now requires ConversationMonitor environment
