//
//  StartupCoordinator.swift
//  ContextifyCore
//
//  Created on 2025-11-05.
//  Orchestrates deterministic startup sequencing for project identity pipeline.
//

import Foundation
import OSLog
import Observation

/// Error types for startup coordination.
public enum StartupError: Error, Equatable {
    case noProjectRootAvailable
    case contextNeverPublished
    case projectCreationFailed(String)
    case invalidProjectRoot(String)
}

/// Orchestrates deterministic startup sequencing for project identity.
///
/// **Purpose:**
/// - Provides single source of truth for active project identity
/// - Ensures project exists in database before any monitoring starts
/// - Coordinates startup ordering across HUD, Switcher, Timeline
/// - Eliminates races from multiple async initialization pipelines
///
/// **Usage:**
/// ```swift
/// // App launch (ContextifyApp.swift)
/// try await StartupCoordinator.shared.start()
///
/// // Wait for initial context (ContentView.swift)
/// let context = try await StartupCoordinator.shared.ready()
/// await monitor.startMonitoring(projectId: context.id)
///
/// // Subscribe to updates (ProjectSwitcherState.swift)
/// for await context in StartupCoordinator.shared.updates {
///     await handleContextUpdate(context)
/// }
///
/// // User-initiated switch (HUDViewModel.swift)
/// try await StartupCoordinator.shared.switchProject(to: newPath)
/// ```
///
/// **Threading:**
/// - All public methods are @MainActor isolated
/// - Database operations run on background threads via Task.detached
/// - State updates always happen on main thread
///
/// **Lifecycle:**
/// - Call `start()` once from app launch
/// - `start()` is idempotent (safe to call multiple times)
/// - Subscribe to `updates` stream for ongoing changes
/// - Use `ready()` to block until first context available
@MainActor
@Observable
public final class StartupCoordinator {
    /// Shared singleton instance.
    public static let shared = StartupCoordinator()

    private let log = Logger(subsystem: "dev.contextify", category: "StartupCoordinator")

    /// Current active project context (nil until first resolution).
    ///
    /// Observable property that updates when project switches.
    /// UI can bind to this directly or subscribe to `updates` stream.
    public private(set) var current: ActiveProjectContext?

    /// Whether coordinator has been started.
    @ObservationIgnored private var isStarted = false

    /// Last published context signature (for deduplication by id + path).
    @ObservationIgnored private var lastSignature: (id: String, path: String)?

    // MARK: - Initialization

    private init() {
        log.info("StartupCoordinator initialized")
    }

    deinit {
        // No cleanup needed
    }

    // MARK: - Public API (Multicast Updates)

    /// Create a fresh update stream for each subscriber.
    ///
    /// **IMPORTANT:** Do NOT use a single shared `AsyncStream` property - that creates unicast
    /// semantics where multiple subscribers compete for elements. Instead, call this method
    /// to get a fresh stream backed by its own NotificationCenter observer.
    ///
    /// Yields new context whenever:
    /// - Initial startup completes (`start()`)
    /// - User switches project (`switchProject()`)
    /// - External project change detected
    ///
    /// **Multicast:** Each call returns an independent stream; all streams receive all updates.
    /// Late subscribers will miss updates that occurred before subscription.
    nonisolated public func updates() -> AsyncStream<ActiveProjectContext> {
        AsyncStream { continuation in
            // Fresh NotificationCenter observer per stream
            nonisolated(unsafe) let token = NotificationCenter.default.addObserver(
                forName: .activeProjectContextDidChange,
                object: nil,
                queue: .main
            ) { note in
                if let ctx = note.object as? ActiveProjectContext {
                    continuation.yield(ctx)
                }
            }

            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    // MARK: - Public API

    /// Start coordinator (call once from app launch).
    ///
    /// Resolves project root using this precedence:
    /// 1. `CONTEXTIFY_PROJECT_ROOT` environment variable
    /// 2. Persisted bookmark/path from UserDefaults
    /// 3. Current working directory (CWD)
    /// 4. Error if none available
    ///
    /// Then ensures project exists in database and publishes context.
    ///
    /// **Thread Safety:** @MainActor isolated, but database operations run off-main.
    /// **Idempotent:** Safe to call multiple times (no-op after first call).
    ///
    /// - Throws: `StartupError` if project resolution fails
    public func start() async throws {
        guard !isStarted else {
            log.warning("StartupCoordinator.start() called while already started (no-op)")
            return
        }

        log.info("🚀 StartupCoordinator starting...")

        // Phase 1: Resolve project root
        let resolvedPath = try await resolveProjectRoot()
        log.info("📁 Resolved project root: \(resolvedPath, privacy: .public)")

        // Phase 2: Ensure DB project exists
        let projectId = try await ensureProjectInDatabase(path: resolvedPath)
        log.info("✅ Project ID: \(projectId, privacy: .public)")

        // Phase 3: Resolve git branch
        let branch = await resolveGitBranch(path: resolvedPath)
        if let branch = branch {
            log.debug("🌿 Git branch: \(branch, privacy: .public)")
        }

        // Phase 4: Create bookmark from resolved path (not stale prefs)
        let bookmark = await Task.detached {
            let url = URL(fileURLWithPath: resolvedPath).resolvingSymlinksInPath()
            return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }.value

        // Phase 5: Persist for next launch
        await Task.detached {
            HUDPreferences.setPersistedRoot(resolvedPath)
        }.value
        log.debug("💾 Persisted project path to UserDefaults for next launch")

        // Phase 6: Create context
        let context = ActiveProjectContext(
            id: projectId,
            path: resolvedPath,
            displayName: URL(fileURLWithPath: resolvedPath).lastPathComponent,
            branch: branch,
            bookmark: bookmark
        )

        // Phase 7: Publish
        await publishContext(context)

        // Mark started only after we have a valid, published context
        isStarted = true

        log.notice("✅ StartupCoordinator ready: \(context.displayName) (id: \(projectId, privacy: .public))")
    }

    /// Wait for initial context (blocking with timeout).
    ///
    /// If context is already available, returns immediately.
    /// Otherwise, blocks until `start()` publishes the first context or timeout expires.
    ///
    /// **Usage Pattern:**
    /// ```swift
    /// // ContentView.swift .task block
    /// let context = try await StartupCoordinator.shared.ready()
    /// await timeline.startMonitoring(projectId: context.id)
    /// ```
    ///
    /// - Returns: The active project context
    /// - Throws: `StartupError.contextNeverPublished` if timeout expires or stream ends without yielding
    public func ready() async throws -> ActiveProjectContext {
        // Fast path: context already available
        if let current = current {
            return current
        }

        // Bounded wait with timeout to prevent startup deadlock
        return try await withThrowingTaskGroup(of: ActiveProjectContext.self) { group in
            // Task 1: Timeout guard (5 seconds)
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw StartupError.contextNeverPublished
            }

            // Task 2: Wait for first context
            group.addTask {
                for await ctx in self.updates() {
                    return ctx
                }
                throw StartupError.contextNeverPublished
            }

            // Return first result (either context or timeout error)
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// Switch to a new project (user action).
    ///
    /// Creates project in database if it doesn't exist, then publishes new context.
    /// All subscribers to `updates` stream will receive the new context.
    ///
    /// **Usage:**
    /// ```swift
    /// // User selects new project in UI
    /// try await StartupCoordinator.shared.switchProject(to: "/path/to/project")
    /// ```
    ///
    /// - Parameter path: Absolute path to new project root
    /// - Throws: `StartupError` if project creation fails
    public func switchProject(to path: String) async throws {
        let startTime = Date()
        log.notice("🔄 [COORD-START] User-initiated switch to project: \(path, privacy: .public)")
        log.info("[SUMM-COORD] StartupCoordinator.switchProject() called for: \(path)")
        log.info("[UIOPT-COORD-START] switchProject() called for: \(path, privacy: .public)")

        // Validate path exists
        let validateStart = Date()
        log.info("[UIOPT-COORD-VALIDATE] Checking if path exists...")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw StartupError.invalidProjectRoot(path)
        }
        log.info("[UIOPT-COORD-VALIDATE] Path validation complete in \(String(format: "%.0f", Date().timeIntervalSince(validateStart) * 1000), privacy: .public)ms")

        // Early exit if already at this path (deduplicate concurrent switches)
        if let last = lastSignature, last.path == path {
            log.debug("🔄 [COORD-DEDUPE] Already switched to \(path), skipping duplicate")
            log.info("[UIOPT-COORD-DONE] Skipped duplicate switch in \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms")
            return
        }

        // Ensure project exists in database
        let dbStart = Date()
        log.info("💾 [COORD-DB-START] Looking up/creating project in database (elapsed: \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s)")
        log.info("[UIOPT-COORD-DB-START] Starting database lookup/creation...")
        let projectId = try await ensureProjectInDatabase(path: path)
        log.info("💾 [COORD-DB-DONE] Database lookup complete in \(String(format: "%.3f", Date().timeIntervalSince(dbStart)))s | Total: \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")
        log.info("[UIOPT-COORD-DB-DONE] Database operation complete in \(String(format: "%.0f", Date().timeIntervalSince(dbStart) * 1000), privacy: .public)ms")

        // Resolve git branch
        let gitStart = Date()
        log.info("[UIOPT-COORD-GIT-START] Resolving git branch...")
        let branch = await resolveGitBranch(path: path)
        log.info("[UIOPT-COORD-GIT-DONE] Git resolution complete in \(String(format: "%.0f", Date().timeIntervalSince(gitStart) * 1000), privacy: .public)ms")

        // Create bookmark from switch target path (not stale prefs)
        let bookmarkStart = Date()
        log.info("[UIOPT-COORD-BOOKMARK-START] Creating security-scoped bookmark...")
        let bookmark = await Task.detached {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }.value
        log.info("[UIOPT-COORD-BOOKMARK-DONE] Bookmark creation complete in \(String(format: "%.0f", Date().timeIntervalSince(bookmarkStart) * 1000), privacy: .public)ms")

        // Create new context
        let contextStart = Date()
        log.info("[UIOPT-COORD-CONTEXT-START] Creating ActiveProjectContext object...")
        let context = ActiveProjectContext(
            id: projectId,
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            branch: branch,
            bookmark: bookmark
        )
        log.info("[UIOPT-COORD-CONTEXT-DONE] Context creation complete in \(String(format: "%.0f", Date().timeIntervalSince(contextStart) * 1000), privacy: .public)ms")

        // Persist for next launch
        let persistStart = Date()
        log.info("[UIOPT-COORD-PERSIST-START] Persisting project path to UserDefaults...")
        await Task.detached {
            HUDPreferences.setPersistedRoot(path)
        }.value
        log.info("[UIOPT-COORD-PERSIST-DONE] Persistence complete in \(String(format: "%.0f", Date().timeIntervalSince(persistStart) * 1000), privacy: .public)ms")

        // Publish
        let publishStart = Date()
        log.info("📢 [COORD-PUBLISH-START] Publishing context (elapsed: \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s)")
        log.info("[SUMM-COORD] Publishing ActiveProjectContext (id: \(projectId), path: \(path))")
        log.info("[UIOPT-COORD-PUBLISH-START] Publishing context to subscribers...")
        await publishContext(context)
        log.info("📢 [COORD-PUBLISH-DONE] Publish complete in \(String(format: "%.3f", Date().timeIntervalSince(publishStart)))s | Total: \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")
        log.info("[SUMM-COORD] ActiveProjectContext published, subscribers should receive update")
        log.info("[UIOPT-COORD-PUBLISH-DONE] Publish complete in \(String(format: "%.0f", Date().timeIntervalSince(publishStart) * 1000), privacy: .public)ms")

        log.notice("✅ [COORD-END] Switched to: \(context.displayName) (id: \(projectId, privacy: .public)) in \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s")
        log.info("[UIOPT-COORD-DONE] Total switchProject() time: \(String(format: "%.0f", Date().timeIntervalSince(startTime) * 1000), privacy: .public)ms")
    }

    // MARK: - Private Helpers

    /// Resolve project root using precedence order.
    private func resolveProjectRoot() async throws -> String {
        // Priority 1: Environment variable
        if let envRoot = ProcessInfo.processInfo.environment["CONTEXTIFY_PROJECT_ROOT"] {
            log.debug("📍 Using CONTEXTIFY_PROJECT_ROOT: \(envRoot, privacy: .public)")
            return envRoot
        }

        // Priority 2: Bookmark (sandboxed builds)
        let bookmarkURL = await Task.detached {
            return HUDPreferences.resolveBookmark()
        }.value
        if let bookmarkURL {
            let path = bookmarkURL.resolvingSymlinksInPath().path
            log.debug("📍 Using bookmark: \(path, privacy: .public)")
            return path
        }

        // Priority 3: Persisted path (UserDefaults)
        let persistedPath = await Task.detached {
            return HUDPreferences.getPersistedRoot()
        }.value
        if let persistedPath, !persistedPath.isEmpty {
            log.debug("📍 Using persisted path: \(persistedPath, privacy: .public)")
            return persistedPath
        }

        // Priority 4: Current working directory
        let cwd = FileManager.default.currentDirectoryPath
        if cwd != "/" {
            log.debug("📍 Using CWD: \(cwd, privacy: .public)")
            return cwd
        }

        // No valid root available
        log.error("❌ No project root available (no env var, bookmark, persisted path, or valid CWD)")
        throw StartupError.noProjectRootAvailable
    }

    /// Ensure project exists in database (create if needed).
    ///
    /// Runs off main thread to avoid blocking UI.
    ///
    /// - Parameter path: Absolute path to project root
    /// - Returns: Stable project ID from database
    /// - Throws: `StartupError.projectCreationFailed` if DB operation fails
    private func ensureProjectInDatabase(path: String) async throws -> String {
        let funcStart = Date()
        log.info("[UIOPT-COORD-DB-FUNC-START] ensureProjectInDatabase() called")

        // Run database operation on background thread (inherits cancellation)
        log.info("[UIOPT-COORD-DB-TASK-START] Spawning background Task...")
        let result = await Task(priority: .userInitiated) { () -> Result<String, Error> in
            let taskStart = Date()
            self.log.info("[UIOPT-COORD-DB-TASK-EXEC] Task executing on background thread")

            // Check early cancellation
            if Task.isCancelled {
                self.log.info("[UIOPT-COORD-DB-TASK-CANCEL] Task was cancelled")
                return .failure(CancellationError())
            }

            do {
                let orchStart = Date()
                self.log.info("[UIOPT-COORD-DB-ORCH-START] Creating TranscriptOrchestrator...")
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                self.log.info("[UIOPT-COORD-DB-ORCH-DONE] Orchestrator created in \(String(format: "%.0f", Date().timeIntervalSince(orchStart) * 1000), privacy: .public)ms")

                let url = URL(fileURLWithPath: path)
                let name = url.lastPathComponent

                let projStart = Date()
                self.log.info("[UIOPT-COORD-DB-PROJ-START] Calling getOrCreateProject...")
                let projectId = try orchestrator.getOrCreateProject(
                    name: name,
                    rootPath: path
                )
                self.log.info("[UIOPT-COORD-DB-PROJ-DONE] getOrCreateProject returned in \(String(format: "%.0f", Date().timeIntervalSince(projStart) * 1000), privacy: .public)ms")

                let taskElapsed = Date().timeIntervalSince(taskStart)
                self.log.info("[UIOPT-COORD-DB-TASK-DONE] Task complete in \(String(format: "%.0f", taskElapsed * 1000), privacy: .public)ms")
                return .success(projectId)
            } catch {
                self.log.error("[UIOPT-COORD-DB-TASK-ERROR] Task failed: \(error.localizedDescription, privacy: .public)")
                return .failure(error)
            }
        }.value

        log.info("[UIOPT-COORD-DB-TASK-AWAIT] Task.value returned")

        switch result {
        case .success(let projectId):
            let funcElapsed = Date().timeIntervalSince(funcStart)
            log.info("[UIOPT-COORD-DB-FUNC-DONE] ensureProjectInDatabase() complete in \(String(format: "%.0f", funcElapsed * 1000), privacy: .public)ms")
            return projectId
        case .failure(let error):
            let message = error.localizedDescription
            self.log.error("❌ Failed to create project: \(message, privacy: .public)")
            throw StartupError.projectCreationFailed(message)
        }
    }

    /// Resolve git branch for project (if git repository).
    ///
    /// - Parameter path: Absolute path to project root
    /// - Returns: Branch name, or nil if not a git repository
    private func resolveGitBranch(path: String) async -> String? {
        let funcStart = Date()
        log.info("[UIOPT-COORD-GIT-FUNC-START] resolveGitBranch() called")

        // Run git detection on background thread (file I/O)
        log.info("[UIOPT-COORD-GIT-TASK-START] Spawning detached Task...")
        let result = await Task.detached(priority: .utility) { () -> String? in
            let taskStart = Date()
            self.log.info("[UIOPT-COORD-GIT-TASK-EXEC] Task executing on background thread")

            let url = URL(fileURLWithPath: path)

            let findStart = Date()
            self.log.info("[UIOPT-COORD-GIT-FIND-START] Calling GitRepositoryResolver.findGitRoot...")
            guard let gitRoot = GitRepositoryResolver.findGitRoot(startingAt: url) else {
                self.log.info("[UIOPT-COORD-GIT-FIND-NONE] No git root found in \(String(format: "%.0f", Date().timeIntervalSince(findStart) * 1000), privacy: .public)ms")
                return nil
            }
            self.log.info("[UIOPT-COORD-GIT-FIND-DONE] Git root found in \(String(format: "%.0f", Date().timeIntervalSince(findStart) * 1000), privacy: .public)ms")

            let infoStart = Date()
            self.log.info("[UIOPT-COORD-GIT-INFO-START] Calling GitRepositoryResolver.computeGitInfo...")
            let info = GitRepositoryResolver.computeGitInfo(
                environment: ProcessInfo.processInfo.environment,
                persistedPath: path,
                currentRoot: gitRoot,
                autoPersist: false  // Don't persist during resolution
            )
            self.log.info("[UIOPT-COORD-GIT-INFO-DONE] computeGitInfo returned in \(String(format: "%.0f", Date().timeIntervalSince(infoStart) * 1000), privacy: .public)ms")

            let taskElapsed = Date().timeIntervalSince(taskStart)
            self.log.info("[UIOPT-COORD-GIT-TASK-DONE] Task complete in \(String(format: "%.0f", taskElapsed * 1000), privacy: .public)ms")
            return info.branch
        }.value

        log.info("[UIOPT-COORD-GIT-TASK-AWAIT] Task.value returned")

        let funcElapsed = Date().timeIntervalSince(funcStart)
        log.info("[UIOPT-COORD-GIT-FUNC-DONE] resolveGitBranch() complete in \(String(format: "%.0f", funcElapsed * 1000), privacy: .public)ms")
        return result
    }

    /// Publish context to subscribers.
    ///
    /// Deduplicates by project ID to avoid redundant updates.
    ///
    /// - Parameter context: New active project context
    private func publishContext(_ context: ActiveProjectContext) async {
        let funcStart = Date()
        log.info("[UIOPT-COORD-PUBLISH-FUNC-START] publishContext() called")

        // Deduplicate by (id, path) tuple - catches both ID and path changes
        log.info("[UIOPT-COORD-PUBLISH-DEDUPE] Checking for duplicate...")
        if let sig = lastSignature, sig.id == context.id, sig.path == context.path {
            log.debug("🔇 Skipping duplicate context publish for project: \(context.id, privacy: .public)")
            log.info("[UIOPT-COORD-PUBLISH-FUNC-SKIP] Skipped duplicate publish in \(String(format: "%.0f", Date().timeIntervalSince(funcStart) * 1000), privacy: .public)ms")
            return
        }
        log.info("[UIOPT-COORD-PUBLISH-DEDUPE] Not a duplicate, continuing...")

        let sigStart = Date()
        log.info("[UIOPT-COORD-PUBLISH-SIG] Updating lastSignature...")
        lastSignature = (id: context.id, path: context.path)
        log.info("[UIOPT-COORD-PUBLISH-SIG] Signature updated in \(String(format: "%.0f", Date().timeIntervalSince(sigStart) * 1000), privacy: .public)ms")

        let currentStart = Date()
        log.info("[UIOPT-COORD-PUBLISH-CURRENT] Setting self.current...")
        self.current = context
        log.info("[UIOPT-COORD-PUBLISH-CURRENT] Current set in \(String(format: "%.0f", Date().timeIntervalSince(currentStart) * 1000), privacy: .public)ms")

        let notifStart = Date()
        log.info("[UIOPT-COORD-PUBLISH-NOTIF] Posting NotificationCenter notification...")
        NotificationCenter.default.post(name: .activeProjectContextDidChange, object: context)
        log.info("[UIOPT-COORD-PUBLISH-NOTIF] Notification posted in \(String(format: "%.0f", Date().timeIntervalSince(notifStart) * 1000), privacy: .public)ms")

        log.debug("📢 Published context: \(context.displayName) (id: \(context.id, privacy: .public), path: \(context.path, privacy: .public))")

        let funcElapsed = Date().timeIntervalSince(funcStart)
        log.info("[UIOPT-COORD-PUBLISH-FUNC-DONE] publishContext() complete in \(String(format: "%.0f", funcElapsed * 1000), privacy: .public)ms")
    }

}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the active project context changes.
    ///
    /// The notification object is the new `ActiveProjectContext`.
    static let activeProjectContextDidChange = Notification.Name("dev.contextify.activeProjectContextDidChange")
}

// MARK: - URL Extension for Bookmark Data

private extension URL {
    /// Get bookmark data for this URL (used for security-scoped access).
    var bookmarkData: Data? {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = Sandbox.isSandboxed ? [.withSecurityScope] : []
        return try? bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        return nil
        #endif
    }
}
