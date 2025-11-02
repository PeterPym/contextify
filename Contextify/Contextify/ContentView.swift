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

// Sheet presentation options
enum ActiveSheet: Identifiable, Sendable {
    case embeddingTest
    case databaseTest
    case batchEmbedding
    case semanticSearch

    var id: String {
        switch self {
        case .embeddingTest: return "embeddingTest"
        case .databaseTest: return "databaseTest"
        case .batchEmbedding: return "batchEmbedding"
        case .semanticSearch: return "semanticSearch"
        }
    }
}

struct ContentView: View {
    @Environment(HUDViewModel.self) private var model
    @Environment(ConversationMonitor.self) private var timeline
    @Environment(DeveloperMode.self) private var devMode
    // Observe project switcher so body re-renders when project list changes
    @Environment(ProjectSwitcherState.self) private var projectSwitcher
    @State private var showToast = false
    @State private var toastText = ""
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var activeSheet: ActiveSheet?

    var body: some View {
        VStack(spacing: 0) {
            // Project switcher (top navigation)
            // Show only when we have 2+ projects (otherwise just wastes vertical space)
            if projectSwitcher.allProjects.count >= 2 {
                ProjectSwitcherView()
                Divider()
            }

            // Project header (always visible for v1.0)
            projectHeader
            Divider()

            // Timeline - full width, no sidebar
            SurfaceCard(includeShadow: false, verticalPadding: Layout.containerPadding, horizontalPadding: Layout.cardPadding) {
                ConversationTimelineView()
            }
            .frame(
                minWidth: timeline.isCollapsed ? Layout.timelineMinCollapsed : Layout.timelineMin,
                maxWidth: .infinity
            )
            .padding(Layout.containerPadding)

            // Status bar footer
            StatusBarView()
        }
        .background(WindowTitleWriter(title: "Contextify"))
        .overlay(alignment: .top) { toast }
        .frame(
            minWidth: Layout.timelineMin,  // Timeline-only minimum for v1.0
            minHeight: 360
        )
        .task {
            // Async startup to avoid blocking main thread with file I/O
            await model.startup()
            TimelineIntegration.shared.startMonitoring()

            // Note: ProjectSwitcherState.shared.start() is called in ContextifyApp init
            // for deterministic startup order. Do not call it here.
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
                presentToast(msg)
            }
        }
    }

    // MARK: - Project Header (Extracted for v1.0)

    /// Project header - always visible at top, extracted from sidebar for v1.0 release
    private var projectHeader: some View {
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
                    .frame(minWidth: 28, minHeight: 28)
                    .contentShape(Rectangle())
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
                Button(action: { activeSheet = .embeddingTest }) {
                    Image(systemName: "testtube.2")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .help("Test Embedding Service")

                Button(action: { activeSheet = .databaseTest }) {
                    Image(systemName: "cylinder")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
                .help("Test Embedding Database")
            }

            Button(action: { activeSheet = .batchEmbedding }) {
                Image(systemName: "gearshape.2")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .help("Batch Embedding Generation")

            Button(action: { activeSheet = .semanticSearch }) {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .frame(minWidth: 28, minHeight: 28)
            .contentShape(Rectangle())
            .help("Semantic Search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .embeddingTest:
                EmbeddingTestView()
            case .databaseTest:
                EmbeddingDatabaseTestView()
            case .batchEmbedding:
                BatchEmbeddingView()
            case .semanticSearch:
                SemanticSearchView()
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
                        toastDismissTask?.cancel()
                        toastDismissTask = nil
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

// MARK: - Layout Constants

private struct Layout {
    static let dividerThickness: CGFloat = 1

    // Timeline/conversation log
    static let timelineMin: CGFloat = 340  // User requirement: timeline min 340px
    static let timelineMinCollapsed: CGFloat = 52

    static let containerPadding: CGFloat = 8
    static let cardPadding: CGFloat = 12
}

private extension ContentView {
    @discardableResult
    @MainActor
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

    func presentToast(_ message: String, duration: TimeInterval? = nil) {
        // Cancel any existing auto-dismiss task to prevent premature hiding of new toast
        toastDismissTask?.cancel()
        toastDismissTask = nil

        toastText = message
        withAnimation { showToast = true }
        let autoDismissDuration = duration ?? 2  // Default 2 seconds
        if autoDismissDuration > 0 {
            toastDismissTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(autoDismissDuration))
                withAnimation { showToast = false }
                toastDismissTask = nil
            }
        }
        // If duration is 0, toast persists until manually dismissed
    }
}
