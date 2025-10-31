//
//  ContentView.swift
//  Contextify
//
//  Created by Rob Banagale on 9/13/25.
//

import SwiftUI
import AppKit
import OSLog

import ContextifyCore
private let uiLog = Logger(subsystem: "dev.contextify", category: "UI")

extension Notification.Name {
    static let toggleComposeSidebar = Notification.Name("toggleComposeSidebar")
}

struct ContentView: View {
    @Environment(HUDViewModel.self) private var model
    @Environment(ConversationMonitor.self) private var timeline
    @Environment(DeveloperMode.self) private var devMode
    @Environment(\.scenePhase) private var scenePhase
    // Singleton reference - no @State needed since we're not replacing the reference
    private let projectSwitcher = ProjectSwitcherState.shared
    @State private var showToast = false
    @State private var toastText = ""
    @State private var showEmbeddingTest = false
    @State private var showDatabaseTest = false
    @State private var showBatchEmbedding = false
    @State private var showSemanticSearch = false
    @State private var workspaceObserver: NSObjectProtocol?

    // Persisted column visibility
    @AppStorage("ui.columnVisibility") private var columnVisibilityStore: String = "all"
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // Persisted sidebar width (compose)
    @AppStorage("ui.composeSidebarWidth") private var composeSidebarWidthStore: Double = 520
    private var composeIdeal: CGFloat { CGFloat(composeSidebarWidthStore).clamped(480, 640) }

    init() {
        _columnVisibility = State(initialValue: Self.visibilityFromStore(columnVisibilityStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Project switcher (top navigation)
            // Show only when we have 2+ projects (otherwise just wastes vertical space)
            if projectSwitcher.allProjects.count >= 2 {
                ProjectSwitcherView()
                    .environment(projectSwitcher)
            }

            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Sidebar: Compose panel
                VStack(alignment: .leading, spacing: 16) {
                    headerWithoutComposeToggle
                    Divider()
                    // REMOVED UI (2025-10-02): Contextify file/URL ingestion features
                    // Previously here:
                    // - urlEntry: TextField + "Ingest" button for URL ingestion
                    // - IngestDropZone: Drag-and-drop zone for files
                    // - controls: "New Session", "Checkpoint", "Reveal Outputs" buttons
                    // - Session label (e.g., "Session-001")
                    // - Status display / Last output URL
                    //
                    // These features created timestamped Markdown artifacts in ~/Contextify/outputs
                    // For restoration, see git history or build/notes/archive/2025-10-02-compose-panel.md
                    composeSection
                }
                .padding(16)
                .navigationSplitViewColumnWidth(min: 480, ideal: composeIdeal, max: 640)
                .background(SidebarWidthReader(width: Binding(
                    get: { CGFloat(composeSidebarWidthStore) },
                    set: { composeSidebarWidthStore = Double($0) }
                )))
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation { columnVisibility.toggleSplitVisibility() }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel(columnVisibility == .all ? "Hide compose panel" : "Show compose panel")
                        .help(columnVisibility == .all ? "Hide compose panel" : "Show compose panel")
                        .padding(4)
                    }
                }
            } detail: {
                // Detail: Timeline (width synced to internal collapsed state)
                ConversationTimelineView()
                    .modifier(DetailWidthSync(isCollapsed: timeline.isCollapsed))
            }
            .navigationSplitViewStyle(.balanced)

            // Status bar footer
            StatusBarView()
        }
        .background(WindowTitleWriter(title: "Contextify"))
        .overlay(alignment: .top) { toast }
        .frame(minHeight: 360)
        .task {
            // Async startup to avoid blocking main thread with file I/O
            await model.startup()
            await refreshSession()
            TimelineIntegration.shared.startMonitoring()

            // Note: ProjectSwitcherState.shared.start() is called in ContextifyApp init
            // for deterministic startup order. Do not call it here.

            // Monitor iTerm2 activation for automatic session refresh
            setupWorkspaceMonitoring()
        }
        .onDisappear {
            cleanupWorkspaceMonitoring()
        }
        .onChange(of: scenePhase) { _, phase in
            // Clean up on background; re-setup on active (if not already set up)
            if phase == .background {
                cleanupWorkspaceMonitoring()
            } else if phase == .active, workspaceObserver == nil {
                setupWorkspaceMonitoring()
            }
        }
        .onChange(of: columnVisibility) { _, v in
            columnVisibilityStore = Self.visibilityToStore(v)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleComposeSidebar)) { _ in
            withAnimation { columnVisibility.toggleSplitVisibility() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .contextifyShowToast)) { notification in
            guard let payload = notification.userInfo?[ToastPayloadKey.message] as? String else { return }
            let duration = notification.userInfo?[ToastPayloadKey.duration] as? TimeInterval
            presentToast(payload, duration: duration)
        }
        .alert("Project Root", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: model.state) { _, newState in
            if case .success(let msg) = newState {
                toastText = msg
                withAnimation { showToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showToast = false }
                }
            }
        }
    }

    private var headerWithoutComposeToggle: some View {
        HStack(spacing: 12) {
            if let projectPath = model.projectRootURL?.path {
                HStack(spacing: 4) {
                    Button {
                        let ok = pickProjectRoot()
                        uiLog.info("Open project result=\(ok, privacy: .public)")
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Open project...")

                    Text(model.projectDisplayName)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    ProjectBadgesView(projectPath: projectPath)
                }
                Label(model.branchDisplay, systemImage: "arrow.branch")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } else {
                Button("Open project...") {
                    let ok = pickProjectRoot()
                    uiLog.info("Open project result=\(ok, privacy: .public)")
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("set-project-root")
            }
            Spacer()

            // Developer-only test buttons (hidden by default)
            if devMode.isEnabled {
              Button(action: { showEmbeddingTest.toggle() }) {
                  Image(systemName: "testtube.2")
              }
              .buttonStyle(.borderless)
              .help("Test Embedding Service")

              Button(action: { showDatabaseTest.toggle() }) {
                  Image(systemName: "cylinder")
              }
              .buttonStyle(.borderless)
              .help("Test Embedding Database")
            }

            Button(action: { showBatchEmbedding.toggle() }) {
                Image(systemName: "gearshape.2")
            }
            .buttonStyle(.borderless)
            .help("Batch Embedding Generation")

            Button(action: { showSemanticSearch.toggle() }) {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Semantic Search")
        }
        .sheet(isPresented: $showEmbeddingTest) {
            EmbeddingTestView()
        }
        .sheet(isPresented: $showDatabaseTest) {
            EmbeddingDatabaseTestView()
        }
        .sheet(isPresented: $showBatchEmbedding) {
            BatchEmbeddingView()
        }
        .sheet(isPresented: $showSemanticSearch) {
            SemanticSearchView()
        }
    }

    private var composeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Session header
            HStack {
                Text("Send to:")
                    .foregroundStyle(.secondary)
                if let sessionName = model.targetSessionName {
                    Text("✳ \(sessionName)")
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("iTerm2 (not running)")
                        .foregroundStyle(.tertiary)
                }
                Button(action: { Task { await refreshSession() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh iTerm2 session")
                Spacer()
            }
            .font(.subheadline)

            // Text area
            FocusableTextView(text: Binding(
                get: { model.composeText },
                set: { model.composeText = $0 }
            ))
            .frame(minHeight: 120)

            // Send button
            HStack {
                Spacer()
                Button("Send") {
                    Task { await sendToTerminal() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.composeText.isEmpty)
            }
        }
    }

    private var toast: some View {
        Group {
            if showToast {
                HStack(spacing: 8) {
                    Text(toastText)
                        .fixedSize(horizontal: false, vertical: true)  // Allow multiline
                    Button(action: {
                        withAnimation { showToast = false }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
                .padding(.horizontal, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

#Preview { ContentView().environment(HUDViewModel()) }

// MARK: - NavigationSplitView Helpers

private extension NavigationSplitViewVisibility {
    mutating func toggleSplitVisibility() {
        self = (self == .all) ? .detailOnly : .all
    }
}

private extension ContentView {
    static func visibilityFromStore(_ s: String) -> NavigationSplitViewVisibility {
        switch s {
        case "detailOnly": return .detailOnly
        case "all": fallthrough
        default: return .all
        }
    }
    static func visibilityToStore(_ v: NavigationSplitViewVisibility) -> String {
        (v == .detailOnly) ? "detailOnly" : "all"
    }
}

struct DetailWidthSync: ViewModifier {
    let isCollapsed: Bool
    func body(content: Content) -> some View {
        let min = isCollapsed ? 52 : 320
        let ideal = isCollapsed ? 52 : 440
        content.navigationSplitViewColumnWidth(min: CGFloat(min), ideal: CGFloat(ideal))
    }
}

struct SidebarWidthReader: View {
    @Binding var width: CGFloat
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: SidebarWidthKey.self, value: proxy.size.width)
        }
        .onPreferenceChange(SidebarWidthKey.self) { new in
            guard abs(new - width) > 1.0 else { return }

            // Cancel existing debounce task
            debounceTask?.cancel()

            // Create new debounced write (50ms delay)
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                guard !Task.isCancelled else { return }
                width = new
            }
        }
    }
}

private struct SidebarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension CGFloat {
    func clamped(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(self, max))
    }
}

private extension ContentView {
    @discardableResult
    func pickProjectRoot() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.urls.first {
            let result = model.setProjectRoot(url: url)
            switch result {
            case .success(let root):
                #if DEBUG
                uiLog.info("Open project path=\(root.path, privacy: .public)")
                #else
                uiLog.info("Open project path=\(root.path, privacy: .private)")
                #endif
                return true
            case .failure(let error):
                uiLog.error("Failed to open project: \(String(describing: error), privacy: .public)")
                return false
            }
        }
        return false
    }

    func refreshSession() async {
        model.targetSessionName = await ITerm2Bridge.getCurrentSessionName()
    }

    func sendToTerminal() async {
        let textToSend = model.composeText
        let currentLine = await TerminalContentReader.shared.captureCurrentLineFast()

        if let currentLine, !currentLine.isEmpty {
            TerminalTextHistory.shared.push(currentLine)
        }

        let result = await ITerm2Bridge.send(text: textToSend, newline: false, mode: .replace(existingLine: currentLine))
        switch result {
        case .success:
            model.lastCapturedTerminalText = textToSend
            model.composeText = ""
            presentToast("Sent to iTerm2 (Cmd+Z to undo)")
            TimelineIntegration.shared.requestManualRefresh(trigger: .hudSend)
        case .failure(let error):
            presentToast("Failed: \(error.localizedDescription)")
        }
    }

    func presentToast(_ message: String, duration: TimeInterval? = nil) {
        toastText = message
        withAnimation { showToast = true }
        let autoDismissDuration = duration ?? 2  // Default 2 seconds
        if autoDismissDuration > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDuration) {
                withAnimation { showToast = false }
            }
        }
        // If duration is 0, toast persists until manually dismissed
    }

    func cleanupWorkspaceMonitoring() {
        if let token = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            workspaceObserver = nil
            uiLog.debug("Workspace observer removed")
        }
    }

    func setupWorkspaceMonitoring() {
        // Prevent duplicate observers if called again
        guard workspaceObserver == nil else {
            uiLog.debug("Workspace observer already set up, skipping")
            return
        }

        // Observe when iTerm2 becomes active to auto-refresh session name
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak model] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

            // Check if iTerm2 was activated
            if app.bundleIdentifier == "com.googlecode.iterm2" {
                // AppleScript/ScriptingBridge calls must run on MainActor
                Task { @MainActor [weak model] in
                    let sessionName = await ITerm2Bridge.getCurrentSessionName()
                    if let sessionName {
                        model?.targetSessionName = sessionName
                    } else {
                        // Session name fetch returned nil (iTerm2 not responding or no session)
                        uiLog.debug("iTerm2 session name unavailable")
                    }
                }
            }
        }

        uiLog.debug("Workspace observer set up for iTerm2 activation")
    }
}
