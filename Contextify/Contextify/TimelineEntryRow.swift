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
    @Environment(\.openWindow) private var openWindow
    @Environment(ConversationMonitor.self) private var monitor

    // SwiftUI will use TimelineEntry.hash for equality (onScrollToEntry closure ignored)
    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.entry == rhs.entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(entry.summary)
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
            Button("Copy Summary") { copy(entry.summary) }
            Button("Copy Detail") { copy(entry.detail) }
            Button("Copy Both as JSON") { copyAsJSON() }

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
            if entry.action == .nonSummarizable {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("No summary available (non-summarizable content)")
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
                .help("Reveal in transcript inventory")
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

    private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
        switch provider {
        case .claudeCode: return .orange
        case .codexCLI: return .white
        case .other: return .gray
        }
    }
}

// MARK: - Color Scheme
private extension Color {
    /// Contextify app color scheme
    /// Full spec: build/notes/design-reference/color-scheme.md

    // Primary colors
    static let contextifyBlue = Color(red: 0.290, green: 0.482, blue: 0.655)   // #4A7BA7 - User/directive actions
    static let contextifyGreen = Color(red: 0.318, green: 0.659, blue: 0.420)  // #51A86B - Completion/success states
    static let contextifyTaupe = Color(red: 0.608, green: 0.545, blue: 0.494)  // #9B8B7E - Assistant messages

    // Secondary colors (projected from palette)
    static let contextifyRed = Color(red: 0.780, green: 0.306, blue: 0.306)    // #C74E4E - Errors/destructive actions
    static let contextifyYellow = Color(red: 0.831, green: 0.659, blue: 0.306) // #D4A84E - Warnings/pending states
    static let contextifyPurple = Color(red: 0.486, green: 0.408, blue: 0.659) // #7C68A8 - Metadata/generated content
}

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
