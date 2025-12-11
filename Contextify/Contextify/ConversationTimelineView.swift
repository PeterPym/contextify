import SwiftUI
import OSLog
import ContextifyCore

// MARK: - P1-UNREAD-COUNT: Scroll Geometry Tracking

struct ScrollGeometry: Equatable {
    let visibleRect: CGRect
    let contentSize: CGSize
}

struct ScrollGeometryPreferenceKey: PreferenceKey {
    static var defaultValue: ScrollGeometry? = nil
    static func reduce(value: inout ScrollGeometry?, nextValue: () -> ScrollGeometry?) {
        value = nextValue() ?? value
    }
}

private let viewportVisibilityThreshold: CGFloat = 0.25  // fraction of entry height required to consider it “visible” for summaries

struct ConversationTimelineView: View {
    @Environment(ConversationMonitor.self) private var monitor
    @Environment(ProjectsViewModel.self) private var projectsVM
    @Environment(\.openWindow) private var openWindow

    // Auto-scroll state
    @State private var scrollPositionId: UUID?
    @State private var userHasScrolledUp = false  // True when user manually scrolls away from bottom

    // Info popover state
    @State private var showEmptyStateInfo = false

    // Expansion state - persists which entries are expanded across view redraws
    // Uses entry UUID as key for stable identification
    @State private var expandedEntryIds: Set<UUID> = []

    private let minWidth: CGFloat = 52

    private let log = Logger(subsystem: "dev.contextify", category: "UIRender")

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            timelineContent
        }
        .frame(
            minWidth: minWidth,
            maxWidth: .infinity,
            maxHeight: .infinity
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
        .onChange(of: monitor.entries.count) { oldCount, newCount in
            if newCount > oldCount {
                let delta = newCount - oldCount
                log.info("[VIEW-UPDATE] Timeline entries changed: \(oldCount, privacy: .public)→\(newCount, privacy: .public) (+\(delta, privacy: .public))")
            }
        }
        .onChange(of: monitor.visibleEntries.count) { oldCount, newCount in
            if newCount > oldCount {
                let delta = newCount - oldCount
                log.info("[VIEW-VISIBLE] Visible entries changed: \(oldCount, privacy: .public)→\(newCount, privacy: .public) (+\(delta, privacy: .public))")
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
                // REMOVED: Entire Menu { ... } block
                // - Auto-scroll toggle is redundant with sticky-bottom behavior
                // - Refresh is automatic via file watcher
                // - Clear Timeline can be added to Settings if needed later
        }
        .padding(.vertical, 8)
    }

    private var timelineContent: some View {
        ZStack {
            switch (monitor.phase, monitor.visibleEntries.isEmpty) {
            case (.cold, _), (.loading, true):
                // Loading state - show spinner while fetching or if no entries yet during load
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading conversation…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    log.info("[UIOPT-FIRST-PAINT] content-empty appear (loading)")
                }

            case (.failed, _):
                // Error state
                VStack(spacing: 12) {
                    Text("Couldn't load conversation.")
                        .font(.headline)
                    if let error = monitor.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Retry") {
                        TimelineIntegration.shared.requestManualRefresh(trigger: .manualHotkey)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case (.loaded, true):
                // Loaded but truly empty (no conversation yet)
                emptyState
                    .onAppear {
                        log.info("[UIOPT-FIRST-PAINT] content-empty appear (no entries)")
                    }

            default:
                // Loaded with entries - show timeline
                actualTimelineContent
                    .onAppear {
                        log.info("[UIOPT-FIRST-PAINT] content appear; entries=\(monitor.visibleEntries.count)")
                    }
            }
        }
        .id(monitor.entriesRevision)  // Key the whole container off revision to force branch re-evaluation
    }

    private var actualTimelineContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(monitor.visibleEntries, id: \.id) { entry in
                    TimelineEntryRow(
                        entry: entry,
                        onScrollToEntry: { entryId in
                            // Row linking - not currently used for scroll control
                        },
                        isExpanded: expansionBinding(for: entry.id)
                    )
                    .equatable()  // Critical: activates Equatable conformance to prevent redundant recomputes
                    .id(entry.id)
                }
            }
            .scrollTargetLayout()  // Required for aggregate visibility tracking (macOS 15+)
        }
        .scrollPosition(id: $scrollPositionId, anchor: .bottom)  // Scroll position binding with bottom anchor
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ScrollGeometryPreferenceKey.self,
                    value: ScrollGeometry(
                        visibleRect: proxy.frame(in: .named("scrollContainer")),
                        contentSize: proxy.size
                    )
                )
            }
        )
        .coordinateSpace(name: "scrollContainer")
        .onPreferenceChange(ScrollGeometryPreferenceKey.self) { geometry in
            // P1-UNREAD-COUNT: Track scroll position for unread clearing
            if let geometry = geometry {
                monitor.updateScrollPosition(
                    visibleRect: geometry.visibleRect,
                    contentHeight: geometry.contentSize.height
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // "Jump to Latest" button appears when user has scrolled up
            if userHasScrolledUp && !monitor.visibleEntries.isEmpty {
                Button {
                    log.debug("[SCROLL] Jump to Latest clicked")
                    userHasScrolledUp = false
                    autoScrollToBottomIfNeeded("jumpButton", animated: true)
                } label: {
                    Label("Jump to Latest", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                }
                .buttonStyle(.borderedProminent)
                .tint(.contextifyBlue)
                .padding()
                .transition(.scale.combined(with: .opacity))
            }
        }
        // Aggregate visibility tracking (macOS 15+) - replaces per-row callbacks
        .onScrollTargetVisibilityChange(idType: UUID.self, threshold: viewportVisibilityThreshold) { ids in
            monitor.replaceVisibleSnapshot(ids)
        }
        // Scroll phase tracking for user input detection
        .onScrollPhaseChange { _, newPhase in
            monitor.handleScrollPhaseChange(newPhase)

            guard let lastId = monitor.visibleEntries.last?.id else { return }
            let atBottom = (scrollPositionId == lastId)

            switch newPhase {
            case .interacting, .decelerating:
                if !atBottom && !userHasScrolledUp {
                    log.debug("[SCROLL] User scrolled away from bottom")
                    userHasScrolledUp = true
                }

            case .idle:
                if atBottom && userHasScrolledUp {
                    log.debug("[SCROLL] User returned to bottom; re-enabling auto-scroll")
                    userHasScrolledUp = false
                }

            default:
                break
            }
        }
        // Reset state on project switch and scroll to bottom on initial load / new entries
        .onChange(of: monitor.entriesRevision) { oldRevision, newRevision in
            // When entries go to empty, we treat it as a project switch / full reset
            if monitor.entries.isEmpty {
                log.debug("[SCROLL] Project switch detected, resetting scroll state")
                userHasScrolledUp = false
                scrollPositionId = nil
                expandedEntryIds.removeAll()  // Clear expansion state on project switch
            } else {
                autoScrollToBottomIfNeeded("entriesRevision")
            }
        }
        .onAppear {
            autoScrollToBottomIfNeeded("onAppear")
        }
    }

    /// Centralized auto-scroll helper - only scrolls when user hasn't manually scrolled up
    private func autoScrollToBottomIfNeeded(_ reason: StaticString, animated: Bool = false) {
        guard !userHasScrolledUp else {
            log.debug("[SCROLL] Skipping auto-scroll (\(reason)); userHasScrolledUp == true")
            return
        }

        guard let lastId = monitor.visibleEntries.last?.id else { return }

        log.debug("[SCROLL] Auto-scrolling to bottom (\(reason)) -> \(String(describing: lastId))")

        monitor.beginProgrammaticScroll()
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                scrollPositionId = lastId
            }
        } else {
            scrollPositionId = lastId
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // Show ingestion progress if actively loading
            if projectsVM.isIngesting, let progress = projectsVM.discoveryProgress {
                let _ = log.info("[TIMELINE-LOADING] Showing loading indicator (isIngesting=true, progress=\(progress.projectsCompleted, privacy: .public)/\(progress.projectsTotal, privacy: .public))")
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)

                    VStack(spacing: 4) {
                        Text("Loading conversation history...")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        if let project = progress.currentProject {
                            Text(project)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Text("\(progress.projectsCompleted)/\(progress.projectsTotal) projects")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 32)
            } else if monitor.isAwaitingPrimer && monitor.phase == .loading {
                let _ = log.info("[TIMELINE-LOADING] Awaiting primer completion for active project")
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)

                    VStack(spacing: 4) {
                        Text("Finalizing conversation data…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Hang tight, just a few more seconds.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 32)
            } else {
                let _ = log.info("[TIMELINE-EMPTY] Showing empty state (isIngesting=\(projectsVM.isIngesting, privacy: .public), hasProgress=\(projectsVM.discoveryProgress != nil, privacy: .public))")
                // Normal empty state
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
                }
            }

            // Show different message based on whether transcripts exist
            if monitor.allSessions.isEmpty {
                VStack(spacing: 12) {
                    Text("Use Claude Code or Codex to populate the timeline.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)

                    // Check if user hasn't granted folder permissions (sandboxed build only)
                    #if APPSTORE_BUILD
                    let isSandboxed = true
                    #else
                    let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
                    #endif

                    if isSandboxed {
                        // Show button to grant permissions if sandboxed and no sessions found
                        VStack(spacing: 8) {
                            Text("Need to grant folder access?")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Open Transcript Sources...") {
                                openWindow(id: "transcript-sources")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.top, 8)
                    }
                }
            } else {
                Text("This conversation has not started yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: - Expansion State Management

    /// Creates a binding for tracking whether a specific entry is expanded.
    /// This allows expansion state to persist across view redraws when new entries arrive.
    private func expansionBinding(for entryId: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedEntryIds.contains(entryId) },
            set: { isExpanded in
                if isExpanded {
                    expandedEntryIds.insert(entryId)
                } else {
                    expandedEntryIds.remove(entryId)
                }
            }
        )
    }

}
