import SwiftUI

struct ConversationTimelineView: View {
    @Environment(ConversationMonitor.self) private var monitor
    @Environment(\.openWindow) private var openWindow
    @State private var scrollTask: Task<Void, Never>?

    private let collapsedWidth: CGFloat = 52
    private let expandedWidth: CGFloat = 320
    private let scrollAnchorID = "timeline-scroll-anchor"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if monitor.isCollapsed {
                collapsedContent
            } else {
                timelineContent
            }
        }
        .frame(width: monitor.isCollapsed ? collapsedWidth : expandedWidth)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: monitor.isCollapsed)
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
            if monitor.isCollapsed {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
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

            Button(action: { monitor.toggleCollapsed() }) {
                Image(systemName: monitor.isCollapsed ? "arrow.left.square" : "arrow.right.square")
            }
            .buttonStyle(.plain)
            .help(monitor.isCollapsed ? "Expand timeline" : "Collapse timeline")
        }
        .padding(.horizontal, monitor.isCollapsed ? 12 : 16)
        .padding(.vertical, 12)
    }

    private var collapsedContent: some View {
        VStack {
            Spacer()
            if monitor.isProcessing {
                ProgressView()
            } else {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var timelineContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let error = monitor.lastError {
                        errorBanner(error)
                    }

                    if monitor.visibleEntries.isEmpty {
                        emptyState
                    } else {
                        ForEach(monitor.visibleEntries) { entry in
                            TimelineEntryRow(
                                entry: entry,
                                allEntries: monitor.visibleEntries,
                                onScrollToEntry: { entryId in
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(entryId, anchor: .center)
                                    }
                                }
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .id(entry.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(scrollAnchorID)
                    }
                }
                .padding(16)
            }
            .onChange(of: monitor.visibleEntries.count) { _, _ in
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
            Text("No Activity Yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Use Claude Code in iTerm2 to populate the timeline.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
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
