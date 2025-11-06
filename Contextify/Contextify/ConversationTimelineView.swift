import SwiftUI
import OSLog

struct ConversationTimelineView: View {
    @Environment(ConversationMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow
    @State private var scrollTask: Task<Void, Never>?

    // Info popover state
    @State private var showEmptyStateInfo = false

    private let minWidth: CGFloat = 52
    private let scrollAnchorID = "timeline-scroll-anchor"

    private let log = Logger(subsystem: "dev.contextify", category: "UIRender")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            timelineContent
        }
        .frame(
            minWidth: minWidth,
            maxWidth: .infinity
        )
        .background(Color.clear)
        .overlay(alignment: .bottomTrailing) {
            if monitor.lastError != nil {
                Button {
                    TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .padding(8)
                .help("Timeline fetch failed. Retry now.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                    Text("Conversation Log")
                        .font(.headline)
                    if let last = monitor.lastUpdate {
                        Text("Updated \(last, format: .dateTime.hour().minute().second())")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if monitor.isProcessing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    openWindow(id: "projects")
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Manage Projects")
                Button {
                    openWindow(id: "transcript-inventory")
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Show All Transcripts (\(monitor.allSessions.count))")
                Menu {
                    Button("Refresh Now") {
                        TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
                    }
                    Toggle("Auto-scroll", isOn: Binding(
                        get: { monitor.autoScroll },
                        set: { monitor.autoScroll = $0 }
                    ))
                    Divider()
                    Button(role: .destructive) {
                        monitor.clearEntries()
                    } label: {
                        Label("Clear Timeline", systemImage: "trash")
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
        .padding(.vertical, 8)
    }

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let error = monitor.lastError {
                        errorBanner(error)
                    }

                    if monitor.visibleEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(monitor.visibleEntries) { entry in
                            TimelineEntryRow(
                                entry: entry,
                                onScrollToEntry: { entryId in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(entryId, anchor: .center)
                                    }
                                }
                            )
                            // PERF: Removed transition to reduce animation costs during bulk loads
                            // .transition(.move(edge: .trailing).combined(with: .opacity))
                            .id(entry.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(scrollAnchorID)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: monitor.visibleEntries.count) { _, newCount in
                log.info("[UIOPT-RENDER-ENTRIES] Timeline entry count changed to \(newCount, privacy: .public)")

                // Cancel any pending scroll task
                scrollTask?.cancel()

                guard monitor.autoScroll, !monitor.visibleEntries.isEmpty else { return }

                // Create new debounced scroll task (150ms delay to coalesce rapid updates)
                scrollTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(scrollAnchorID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.title3)
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                Text("No Activity Yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                InfoButton(isPresented: $showEmptyStateInfo)
                    .popover(isPresented: $showEmptyStateInfo) {
                        InfoPopoverContent(
                            title: "About the Timeline",
                            message: emptyStateExplanation
                        )
                    }
            }

            // Show different message based on whether transcripts exist
            if monitor.allSessions.isEmpty {
                Text("Use Claude Code or Codex to populate the timeline.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("This conversation has not started yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var emptyStateExplanation: String {
        """
        The Conversation Timeline displays real-time activity from your Claude Code or Codex CLI sessions:

        • User directives (what you ask Claude to do)
        • Assistant responses (Claude's actions and output)
        • Tool usage (file operations, commands, searches)
        • Request/response status and timing

        Getting Started:
        1. Ensure you have a project set (use "Manage Projects" button)
        2. Start a Claude Code or Codex session in that project
        3. Timeline entries will appear automatically as you work

        The timeline updates in real-time and shows summaries of each conversation turn, making it easy to track what's happening in your AI-assisted development session.
        """
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message)
                .font(.caption)
            Spacer()
            Button("Retry") {
                TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
            }
            .buttonStyle(.link)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.15))
        )
    }

}
