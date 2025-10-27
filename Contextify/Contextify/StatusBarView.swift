//
//  StatusBarView.swift
//  Contextify
//
//  SwiftUI component that renders the status bar footer with Apple Intelligence
//  availability indicator and LLM processing queue status
//

import SwiftUI

struct StatusBarView: View {
    private let queueProvider: (any QueueStatsProvider)?
    @State private var viewModel: StatusBarViewModel

    init(queueProvider: (any QueueStatsProvider)?) {
        self.queueProvider = queueProvider
        self._viewModel = State(initialValue: StatusBarViewModel(queueProvider: queueProvider))
    }

    var body: some View {
        HStack(spacing: 16) {
            // Apple Intelligence indicator
            aiStatusIndicator

            Divider()
                .frame(height: 12)

            // Queue status
            queueStatusView
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
        .task {
            viewModel.start()  // NO AWAIT (start() is sync)
        }
        .onDisappear {
            viewModel.stop()  // Explicit cleanup
        }
        .contentTransition(.opacity)  // Smooth state transitions
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
        switch viewModel.aiStatus {
        case .available: return "Apple Intelligence"
        case .unavailable: return "AI Unavailable"
        case .error: return "AI Error"
        }
    }

    private var aiStatusTooltip: String {
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
        if !viewModel.monitoringActive {
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

        } else if viewModel.recentErrorCount > 0 {
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
            .help(viewModel.topErrorReason ?? "Recent LLM generation errors")
            .accessibilityLabel("\(viewModel.recentErrorCount) generation errors")

        } else if viewModel.isProcessing {
            // Processing state
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

        } else if viewModel.queueDepth > 0 {
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
}

// MARK: - Previews

#Preview("Available + Processing") {
    StatusBarView(queueProvider: MockQueueProvider(
        statsSequence: [
            QueueStats(pending: 12, isProcessing: true, currentBatchSize: 10,
                       estimatedSecondsRemaining: 6, recentErrorCount: 0, topErrorReason: nil)
        ]
    ))
    .frame(width: 600, height: 40)
}

#Preview("Up to Date") {
    StatusBarView(queueProvider: MockQueueProvider(
        statsSequence: [
            QueueStats(pending: 0, isProcessing: false, currentBatchSize: 0,
                       estimatedSecondsRemaining: 0, recentErrorCount: 0, topErrorReason: nil)
        ]
    ))
    .frame(width: 600, height: 40)
}

#Preview("Errors") {
    StatusBarView(queueProvider: MockQueueProvider(
        statsSequence: [
            QueueStats(pending: 0, isProcessing: false, currentBatchSize: 0,
                       estimatedSecondsRemaining: 0, recentErrorCount: 3,
                       topErrorReason: "LLM timeout after retries")
        ]
    ))
    .frame(width: 600, height: 40)
}

#Preview("Not Monitoring") {
    StatusBarView(queueProvider: nil)
        .frame(width: 600, height: 40)
}

#Preview("Many Items") {
    StatusBarView(queueProvider: MockQueueProvider(
        statsSequence: [
            QueueStats(pending: 150, isProcessing: true, currentBatchSize: 10,
                       estimatedSecondsRemaining: 45, recentErrorCount: 0, topErrorReason: nil)
        ]
    ))
    .frame(width: 600, height: 40)
}
