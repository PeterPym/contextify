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

    // Sidebar visibility (replacing columnVisibility)
    @AppStorage("ui.sidebarVisible") private var sidebarVisible: Bool = true
    @State private var isAnimatingSidebar = false

    // Persisted sidebar width (compose)
    @AppStorage("ui.composeSidebarWidth") private var composeSidebarWidthStore: Double = 520
    private var composeSidebarWidth: CGFloat { CGFloat(composeSidebarWidthStore).clamped(Layout.composeMin, Layout.composeMax) }

    var body: some View {
        VStack(spacing: 0) {
            // Project switcher (top navigation)
            // Show only when we have 2+ projects (otherwise just wastes vertical space)
            if projectSwitcher.allProjects.count >= 2 {
                ProjectSwitcherView()
                    .environment(projectSwitcher)
                Divider()
            }

            // Manual HStack layout (replaces NavigationSplitView for better control)
            HStack(spacing: 0) {
                // Compose sidebar (conditionally visible)
                if sidebarVisible {
                    SurfaceCard(includeShadow: false, verticalPadding: Layout.containerPadding, horizontalPadding: Layout.cardPadding) {
                        VStack(alignment: .leading, spacing: 16) {
                            headerWithoutComposeToggle
                            Divider()
                            composeSection
                        }
                    }
                    .frame(width: clampedSidebarWidth(composeSidebarWidth))
                    .transition(.move(edge: .leading))

                    // Resizable divider
                    SidebarGrabber(width: Binding(
                        get: { self.composeSidebarWidth },
                        set: { self.composeSidebarWidthStore = Double($0) }
                    )) { dx in
                        // Drag resize: adjust internal panel widths only, window stays fixed
                        let frame = currentWindow()?.frame ?? .zero
                        let overhead = 2 * Layout.containerPadding + Layout.grabberWidth + Layout.dividerThickness

                        // Calculate requested new compose width
                        let requestedComposeW = composeSidebarWidth + dx

                        // Clamp compose width to window bounds (timeline will enforce its own minimum)
                        let maxComposeForWindow = frame.width - overhead
                        let newComposeW = requestedComposeW.clamped(Layout.composeMin, Swift.min(Layout.composeMax, maxComposeForWindow))

                        // Update persisted width (window stays fixed size)
                        composeSidebarWidthStore = Double(newComposeW)
                    }

                    Rectangle()
                        .frame(width: Layout.dividerThickness)
                        .foregroundStyle(.separator)
                }

                // Timeline (detail) - always visible, takes remaining space
                // Let timeline manage its own min width based on collapse state
                SurfaceCard(includeShadow: false, verticalPadding: Layout.containerPadding, horizontalPadding: Layout.cardPadding) {
                    ConversationTimelineView()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Layout.containerPadding)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        toggleSidebar()
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help(sidebarVisible ? "Hide sidebar" : "Show sidebar")
                }
            }
            .task {
                // Trigger window resize immediately to force layout
                triggerWindowResize()
            }

            // Status bar footer
            StatusBarView()
        }
        .background(WindowTitleWriter(title: "Contextify"))
        .overlay(alignment: .top) { toast }
        .frame(minWidth: 320, minHeight: 360)
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleComposeSidebar)) { _ in
            toggleSidebar()
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

// MARK: - Sidebar Grabber

private struct SidebarGrabber: View {
    @Binding var width: CGFloat
    var onDragDelta: ((CGFloat) -> Void)? = nil

    @State private var lastX: CGFloat?

    var body: some View {
        ZStack {
            // Wide invisible hit area
            Rectangle()
                .fill(Color.clear)
                .frame(width: Layout.grabberWidth)
                .contentShape(Rectangle())

            // Thin visible divider line
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: Layout.dividerThickness)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if let last = lastX {
                        let dx = value.location.x - last
                        onDragDelta?(dx)
                    }
                    lastX = value.location.x
                }
                .onEnded { _ in lastX = nil }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .accessibilityIdentifier("sidebar-grabber")
    }
}

// MARK: - Shared Surface

private struct SurfaceCard<Content: View>: View {
    let content: Content
    let includeShadow: Bool
    let verticalPadding: CGFloat?
    let horizontalPadding: CGFloat?

    init(includeShadow: Bool = true, verticalPadding: CGFloat? = nil, horizontalPadding: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.includeShadow = includeShadow
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
    }

    private let corner: CGFloat = 12
    private let defaultPadding: CGFloat = 12

    var body: some View {
        content
            .padding(.vertical, verticalPadding ?? defaultPadding)
            .padding(.horizontal, horizontalPadding ?? defaultPadding)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.separator.opacity(0.5), lineWidth: 1)
            )
            .if(includeShadow) { view in
                view.shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
            }
    }
}

// Helper for conditional modifiers
private extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Sidebar Toggle & Window Resizing

private struct Layout {
    static let dividerThickness: CGFloat = 1
    static let grabberWidth: CGFloat = 10  // Wide hit area for easy grabbing
    static let animationDuration: TimeInterval = 0.25

    // LEFT side: Compose textarea (needs more space for writing)
    static let composeMin: CGFloat = 400
    static let composeMax: CGFloat = 800

    // RIGHT side: Timeline/conversation log (can collapse very narrow)
    static let timelineMin: CGFloat = 100  // Allow timeline to shrink way down
    static let timelineMinCollapsed: CGFloat = 52

    static let containerPadding: CGFloat = 8
    static let cardPadding: CGFloat = 12
}

extension CGFloat {
    func clamped(_ min: CGFloat, _ max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(self, max))
    }
}

private extension ContentView {
    @MainActor
    func currentWindow() -> NSWindow? {
        if let w = MainWindowTracker.shared.window, w.isVisible { return w }
        return NSApp.keyWindow ?? NSApp.mainWindow
    }

    @MainActor
    func visibleFrame(for window: NSWindow) -> CGRect {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    @MainActor
    func clampedSidebarWidth(_ w: CGFloat) -> CGFloat {
        w.clamped(Layout.composeMin, Layout.composeMax)
    }

    @MainActor
    func clampedWindowWidth(_ requested: CGFloat, in vis: CGRect, min minWidth: CGFloat) -> CGFloat {
        return Swift.max(minWidth, Swift.min(requested, vis.width))
    }

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
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(autoDismissDuration))
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

    @MainActor
    func triggerWindowResize() {
        guard let window = NSApp.windows.first else {
            uiLog.warning("No window found for resize trigger")
            return
        }

        let originalFrame = window.frame
        var nudgedFrame = originalFrame
        nudgedFrame.size.width += 1  // Minimal 1-pixel nudge

        // Resize with animation disabled to make it invisible
        window.setFrame(nudgedFrame, display: true, animate: false)

        // Wait just long enough for layout to recalculate, then restore
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            window.setFrame(originalFrame, display: true, animate: false)
            uiLog.debug("Window resize trigger completed")
        }
    }

    @MainActor
    func toggleSidebar() {
        guard let window = currentWindow() else {
            sidebarVisible.toggle()
            uiLog.warning("No window found for sidebar toggle")
            return
        }

        // Coalesce rapid toggles
        guard !isAnimatingSidebar else { return }
        isAnimatingSidebar = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.animationDuration) {
                self.isAnimatingSidebar = false
            }
        }

        // Capture current state
        let frame = window.frame
        let visFrame = visibleFrame(for: window)
        let rightEdgeX = frame.maxX

        let sidebarWidth = clampedSidebarWidth(composeSidebarWidth) + Layout.dividerThickness

        // Compute target width (anchored right)
        let requestedWidth = sidebarVisible ? (frame.width - sidebarWidth)   // hiding → shrink
                                            : (frame.width + sidebarWidth)   // showing → grow
        // Timeline will enforce its own minimum, so just use a small floor for window
        let minWindowWidth = (sidebarVisible ? 0 : sidebarWidth) + 100 + 2 * Layout.containerPadding
        let newWidth = clampedWindowWidth(requestedWidth, in: visFrame, min: minWindowWidth)

        var newOriginX = rightEdgeX - newWidth
        if newOriginX < visFrame.minX { newOriginX = visFrame.minX }  // don't go off left

        let newFrame = CGRect(x: newOriginX, y: frame.origin.y, width: newWidth, height: frame.height)

        // Start both animations on same tick
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Layout.animationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)

            // Kick off SwiftUI animation concurrently
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: Layout.animationDuration)) {
                    self.sidebarVisible.toggle()
                }
            }
        }

        uiLog.info("Sidebar \(sidebarVisible ? "→ hidden" : "→ visible"); window \(Int(frame.width))→\(Int(newWidth)) (anchored right)")
    }
}
