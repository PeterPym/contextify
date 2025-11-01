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

    // Persisted sidebar width (compose)
    @AppStorage("ui.composeSidebarWidth") private var composeSidebarWidthStore: Double = 520
    private var composeSidebarWidth: CGFloat { CGFloat(composeSidebarWidthStore).clamped(480, 640) }

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
                    SurfaceCard(includeShadow: false, verticalPadding: 8, horizontalPadding: 12) {
                        VStack(alignment: .leading, spacing: 16) {
                            headerWithoutComposeToggle
                            Divider()
                            composeSection
                        }
                    }
                    .frame(width: composeSidebarWidth)
                    .transition(.move(edge: .leading))

                    Divider()
                }

                // Timeline (detail) - always visible, takes remaining space
                SurfaceCard(includeShadow: false, verticalPadding: 8, horizontalPadding: 12) {
                    ConversationTimelineView()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8)
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
        .frame(minWidth: 600, minHeight: 360)
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
        guard let window = NSApp.windows.first else {
            sidebarVisible.toggle()
            uiLog.warning("No window found for sidebar toggle")
            return
        }

        // Capture current state
        let currentFrame = window.frame
        let rightEdgeX = currentFrame.maxX
        let wasVisible = sidebarVisible

        // Calculate new window width
        let sidebarWidth = composeSidebarWidth + 1  // +1 for divider
        let newWidth: CGFloat
        if wasVisible {
            // Hiding sidebar - shrink window
            newWidth = currentFrame.width - sidebarWidth
        } else {
            // Showing sidebar - expand window
            newWidth = currentFrame.width + sidebarWidth
        }

        // Calculate new origin to keep right edge fixed
        let newOrigin = CGPoint(
            x: rightEdgeX - newWidth,
            y: currentFrame.origin.y
        )

        var newFrame = CGRect(
            origin: newOrigin,
            size: CGSize(width: newWidth, height: currentFrame.height)
        )

        // Check screen bounds to prevent window going off-screen
        if let screenFrame = window.screen?.visibleFrame {
            if newFrame.minX < screenFrame.minX {
                newFrame.origin.x = screenFrame.minX
            }
        }

        // Animate window resize and content change together
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }

        // Toggle sidebar visibility with SwiftUI animation
        withAnimation(.easeInOut(duration: 0.25)) {
            sidebarVisible.toggle()
        }

        uiLog.info("Toggled sidebar: \(sidebarVisible ? "visible" : "hidden"), window resized to \(Int(newWidth))px")
    }
}
