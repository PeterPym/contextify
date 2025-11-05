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

    /// Stream of context updates for subscribers.
    ///
    /// Yields new context whenever:
    /// - Initial startup completes (`start()`)
    /// - User switches project (`switchProject()`)
    /// - External project change detected
    ///
    /// **Multicast:** Uses NotificationCenter internally to support multiple concurrent subscribers.
    public let updates: AsyncStream<ActiveProjectContext>

    /// Whether coordinator has been started.
    @ObservationIgnored private var isStarted = false

    /// Last published context signature (for deduplication by id + path).
    @ObservationIgnored private var lastSignature: (id: String, path: String)?

    // MARK: - Initialization

    private init() {
        self.updates = Self.createMulticastStream()

        log.info("StartupCoordinator initialized")
    }

    deinit {
        // No cleanup needed - stream observers manage their own lifecycle
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

        // Phase 5: Create context
        let context = ActiveProjectContext(
            id: projectId,
            path: resolvedPath,
            displayName: URL(fileURLWithPath: resolvedPath).lastPathComponent,
            branch: branch,
            bookmark: bookmark
        )

        // Phase 6: Publish
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
                for await ctx in self.updates {
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
        log.notice("🔄 User-initiated switch to project: \(path, privacy: .public)")

        // Validate path exists
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw StartupError.invalidProjectRoot(path)
        }

        // Ensure project exists in database
        let projectId = try await ensureProjectInDatabase(path: path)
        log.info("✅ Switch target project ID: \(projectId, privacy: .public)")

        // Resolve git branch
        let branch = await resolveGitBranch(path: path)

        // Create bookmark from switch target path (not stale prefs)
        let bookmark = await Task.detached {
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            return try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }.value

        // Create new context
        let context = ActiveProjectContext(
            id: projectId,
            path: path,
            displayName: URL(fileURLWithPath: path).lastPathComponent,
            branch: branch,
            bookmark: bookmark
        )

        // Publish
        await publishContext(context)

        log.notice("✅ Switched to: \(context.displayName) (id: \(projectId, privacy: .public))")
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
        // Run database operation on background thread (inherits cancellation)
        let result = await Task(priority: .userInitiated) { () -> Result<String, Error> in
            // Check early cancellation
            if Task.isCancelled {
                return .failure(CancellationError())
            }

            do {
                let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
                let url = URL(fileURLWithPath: path)
                let name = url.lastPathComponent

                let projectId = try orchestrator.getOrCreateProject(
                    name: name,
                    rootPath: path
                )

                return .success(projectId)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let projectId):
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
        // Run git detection on background thread (file I/O)
        return await Task.detached(priority: .utility) { () -> String? in
            let url = URL(fileURLWithPath: path)
            guard let gitRoot = GitRepositoryResolver.findGitRoot(startingAt: url) else {
                return nil
            }

            let info = GitRepositoryResolver.computeGitInfo(
                environment: ProcessInfo.processInfo.environment,
                persistedPath: path,
                currentRoot: gitRoot,
                autoPersist: false  // Don't persist during resolution
            )

            return info.branch
        }.value
    }

    /// Publish context to subscribers.
    ///
    /// Deduplicates by project ID to avoid redundant updates.
    ///
    /// - Parameter context: New active project context
    private func publishContext(_ context: ActiveProjectContext) async {
        // Deduplicate by (id, path) tuple - catches both ID and path changes
        if let sig = lastSignature, sig.id == context.id, sig.path == context.path {
            log.debug("🔇 Skipping duplicate context publish for project: \(context.id, privacy: .public)")
            return
        }

        lastSignature = (id: context.id, path: context.path)
        self.current = context
        NotificationCenter.default.post(name: .activeProjectContextDidChange, object: context)

        log.debug("📢 Published context: \(context.displayName) (id: \(context.id, privacy: .public), path: \(context.path, privacy: .public))")
    }

    /// Create a multicast AsyncStream backed by NotificationCenter.
    ///
    /// This ensures all subscribers receive every update, unlike a single AsyncStream
    /// which has unicast semantics when multiple iterators are created.
    private static func createMulticastStream() -> AsyncStream<ActiveProjectContext> {
        AsyncStream { continuation in
            // Use nonisolated(unsafe) to avoid Sendable requirement on NSObjectProtocol
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
