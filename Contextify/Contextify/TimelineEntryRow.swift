import SwiftUI
import AppKit
import OSLog

private let log = Logger(subsystem: "dev.contextify.timeline", category: "EntryRow")

extension Notification.Name {
    static let revealTranscript = Notification.Name("revealTranscript")
}

// MARK: - Static Format Styles
fileprivate extension Date.FormatStyle {
    /// Static format style for timeline tooltips - avoids allocation on every render
    static let timelineTooltip: Date.FormatStyle =
        .dateTime
            .hour(.defaultDigits(amPM: .abbreviated))
            .minute()
            .second()
            .weekday(.wide)
            .month(.wide)
            .day()
            .year()
}

struct TimelineEntryRow: View, Equatable {
    let entry: TimelineEntry
    let onScrollToEntry: (UUID) -> Void

    @State private var isExpanded = false
    @State private var showCopiedToast = false
    @State private var showSafetyInfo = false
    @State private var showErrorInfo = false
    @State private var showQueuedInfo = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ConversationMonitor.self) private var monitor

    // SwiftUI will use TimelineEntry.hash for equality (onScrollToEntry closure ignored)
    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            formatWithBackticks(entry.summary)
                .font(.callout)
                .foregroundStyle(.primary)

            if isExpanded {
                Divider()
                Text(entry.detail)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(entry.isError ? .red : entry.kind.accentColor)
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .overlay(alignment: .topTrailing) {
            if showCopiedToast {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
                    .offset(x: -4, y: 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            Button("Copy Message Details as JSON") { copyAsJSON() }

            if let transcriptPath = entry.sourceContext?.filePath {
                Divider()
                Button("Reveal Source Transcript in Finder") {
                    revealTranscriptInFinder(path: transcriptPath)
                }
            }

            if entry.contentSha256 != nil && entry.windowSha256 != nil {
                Divider()
                Button("Regenerate Summary") {
                    regenerateSummary()
                }
            }
        }
        .onAppear {
            log.info("[ROW-APPEAR] Entry rendered: \(entry.id, privacy: .public) kind: \(entry.kind.rawValue, privacy: .public) summary: \(String(entry.summary.prefix(40)), privacy: .public)...")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Use provider-specific icon for assistant messages, default icons for others
            if entry.kind == .assistant, let provider = entry.sourceContext?.provider {
                Image(provider.iconImage)
                    .renderingMode(.template)
                    .foregroundStyle(providerColor(provider))
                    .shadow(
                        color: (colorScheme == .light && provider == .codexCLI) ? .black.opacity(0.7) : .clear,
                        radius: 0.5
                    )
            } else {
                Image(systemName: entry.kind.iconName)
                    .foregroundStyle(entry.kind.accentColor)
            }
            Text(entry.timestamp, format: .dateTime.hour().minute())
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .help(entry.timestamp.formatted(Date.FormatStyle.timelineTooltip))  // Re-enabled with static style
            if case .generatingActive = entry.action {
                // NOTE: Pulsing animation is not working as of 2025-11-07
                // The .symbolEffect(.pulse) modifier is applied but visual pulsing doesn't appear
                // TODO: Investigate why symbol effects aren't animating (possibly SwiftUI/macOS version issue)
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.tertiary)
                    .symbolEffect(.pulse.byLayer, options: .repeating, isActive: true)  // Always pulse when active
                    .help("Summary being generated (active)")
            } else if case .unsummarized = entry.action {
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.tertiary)
                    .help("Unsummarized (will generate when scrolled into view)")
            }
            // Queue-operation indicator (user message sent while Claude was working)
            if entry.kind == .user && entry.isQueued {
                Text("QUEUED")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.8))
                    .cornerRadius(3)
                InfoButton(isPresented: $showQueuedInfo)
                    .popover(isPresented: $showQueuedInfo) {
                        InfoPopoverContent(
                            title: "Queued Message",
                            message: "This message was sent while Claude was actively working on tools. It was received via system reminder and addressed in the response."
                        )
                    }
                    .help("Message sent while Claude was working")
            }
            if entry.action == .nonSummarizable {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("No summary available (non-summarizable content)")
            }
            if entry.isSafetyFiltered {
                InfoButton(isPresented: $showSafetyInfo)
                    .popover(isPresented: $showSafetyInfo) {
                        InfoPopoverContent(
                            title: "Unable to Summarize",
                            message: "This message could not be summarized due to Apple Intelligence content controls.\n\nThe on-device language model's safety filters prevent processing this content. The original message is preserved in the detail view."
                        )
                    }
                    .help("Unable to summarize due to content controls")
            }
            if entry.hasGenerationError {
                InfoButton(isPresented: $showErrorInfo)
                    .popover(isPresented: $showErrorInfo) {
                        InfoPopoverContent(
                            title: "Summary Generation Failed",
                            message: errorMessage(for: entry.generationErrorType)
                        )
                    }
                    .help("Summary generation failed")
            }
            if entry.isDirective {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.contextifyBlue)
                    .accessibilityLabel("User directive")
            } else if entry.isCompletion {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.contextifyGreen)
                    .accessibilityLabel("Task completed")

                // Re-enabled with O(1) lookup API
                if let duration = durationText {
                    Text(duration)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                // Re-enabled with O(1) lookup validation
                if let requestId = entry.requestId,
                   monitor.lookup(requestId) != nil {
                    Button(action: { onScrollToEntry(requestId) }) {
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Jump to original request")
                }
            }
            Spacer()
            if case .revealInInventory = entry.action {
                Button(action: revealInInventory) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Reveal in transcripts")
            }
        }
    }

    /// Calculate duration using O(1) lookup API
    private var durationText: String? {
        guard let requestId = entry.requestId,
              let requestEntry = monitor.lookup(requestId) else {
            return nil
        }

        let duration = entry.timestamp.timeIntervalSince(requestEntry.timestamp)
        guard duration > 0 else { return nil }

        let seconds = Int(duration)
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.minutes, .seconds], maximumUnitCount: 2)
        )
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation(.easeInOut(duration: 0.25)) {
            showCopiedToast = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.25)) {
                showCopiedToast = false
            }
        }
    }

    private func copyAsJSON() {
        var json: [String: Any] = [
            "summary": entry.summary,
            "detail": entry.detail,
            "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
            "entry_id": entry.sourceIdentifier
        ]

        // Add transcript filepath if available
        if let transcriptPath = entry.sourceContext?.filePath {
            json["transcript_path"] = transcriptPath
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        copy(jsonString)
    }

    private func regenerateSummary() {
        guard let contentSha = entry.contentSha256,
              let windowSha = entry.windowSha256 else {
            return
        }

        Task {
            await monitor.regenerateSummary(contentSha256: contentSha, windowSha256: windowSha)
        }
    }

    private func revealTranscriptInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func revealInInventory() {
        guard case .revealInInventory(let transcriptPath) = entry.action else { return }

        // Open the inventory window
        openWindow(id: "transcript-inventory")

        // Post notification to select the transcript
        NotificationCenter.default.post(
            name: .revealTranscript,
            object: nil,
            userInfo: ["path": transcriptPath]
        )
    }

    // Provider color now uses TimelineSourceContext.Provider.color extension (TimelineModels.swift)
    private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
        return provider.color
    }

    /// Format text with backtick-enclosed portions in monospace font
    private func formatWithBackticks(_ text: String) -> Text {
        let parts = text.components(separatedBy: "`")
        var attributed = AttributedString()

        for (index, part) in parts.enumerated() {
            if part.isEmpty { continue }

            var segment = AttributedString(part)
            if index % 2 == 1 {
                // Odd indices are inside backticks - render monospace
                segment.font = .system(.callout, design: .monospaced)
            }
            attributed.append(segment)
        }

        return Text(attributed)
    }

    /// Generate contextual error message based on error type
    private func errorMessage(for errorType: String?) -> String {
        guard let type = errorType else {
            return "An error occurred during summary generation. The original message is preserved in the detail view."
        }

        switch type {
        case "overflow":
            return """
            This conversation entry is too long to summarize (exceeded the maximum token limit for Apple Intelligence).

            The full content remains accessible in the detail view below. No summary will be generated for this entry.
            """

        case "decoding":
            return """
            The AI generated a response in an unexpected format that could not be parsed.

            This is usually caused by malformed system output (bash commands, git output, etc.) in the conversation. The entry remains accessible without a summary.
            """

        case "database":
            return """
            Failed to save the generated summary due to a database error.

            Check available disk space and database permissions. The original message is preserved in the detail view.
            """

        case "unexpected":
            return """
            An unexpected error occurred during summary generation.

            This may indicate a bug or unsupported content format. The original message is preserved in the detail view.
            """

        default:
            return """
            Summary generation failed with error type: \(type)

            The original message is preserved in the detail view.
            """
        }
    }
}

// MARK: - Color Scheme
// NOTE: Color palette moved to SharedExtensions.swift to avoid duplication
// Using colors from SharedExtensions: contextifyBlue, contextifyTaupe, contextifyGreen, etc.

private extension TimelineEntryKind {
    var accentColor: Color {
        switch self {
        case .user:
            // Rich blue - professional, distinct
            return Color.contextifyBlue
        case .assistant:
            // Warm gray/taupe - universal compatibility with any provider branding
            return Color.contextifyTaupe
        case .system:
            return .gray
        }
    }

    var iconName: String {
        switch self {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "gearshape"
        }
    }
}
