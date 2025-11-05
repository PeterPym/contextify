//
//  ActiveProjectContext.swift
//  ContextifyCore
//
//  Created on 2025-11-05.
//  Single source of truth for active project identity.
//

import Foundation

/// Single source of truth for active project identity.
///
/// This struct represents the canonical project context used throughout the app.
/// It provides a stable project ID as the primary key, with filesystem path and
/// other metadata as derived properties.
///
/// **Design Principles:**
/// - `id` is the stable database primary key (never changes)
/// - `path` is metadata that can change (user moves project)
/// - All components receive this context from `StartupCoordinator`
/// - Immutable by design (value type, all `let` properties)
///
/// **Usage:**
/// ```swift
/// // Subscribe to context updates
/// for await context in StartupCoordinator.shared.updates {
///     print("Active project: \(context.displayName) at \(context.path)")
/// }
///
/// // Get current context
/// let context = try await StartupCoordinator.shared.ready()
/// await monitor.startMonitoring(projectId: context.id)
/// ```
@frozen
public struct ActiveProjectContext: Sendable, Equatable {
    /// Stable database project ID (PRIMARY key).
    ///
    /// This ID never changes for a given project, even if the project is moved
    /// or renamed on disk. All database queries should use this ID.
    public let id: String

    /// Filesystem path to project root.
    ///
    /// This is metadata that can change if the user moves the project.
    /// Do not use this for database lookups - use `id` instead.
    public let path: String

    /// Display name for UI presentation.
    ///
    /// Typically derived from the last path component, but can be overridden
    /// by user preferences in the future.
    public let displayName: String

    /// Current git branch (if project is a git repository).
    ///
    /// `nil` if the project is not a git repository or git detection failed.
    public let branch: String?

    /// Security-scoped bookmark data for sandboxed builds.
    ///
    /// Used to maintain file access permissions across app launches.
    /// `nil` for non-sandboxed builds or if no bookmark was created.
    public let bookmark: Data?

    /// Timestamp when this context was created.
    ///
    /// Used for debugging and telemetry. Represents when the coordinator
    /// resolved this project, not when the project was first created in DB.
    public let createdAt: Date

    /// Creates a new active project context.
    ///
    /// - Parameters:
    ///   - id: Stable database project ID
    ///   - path: Filesystem path to project root
    ///   - displayName: Human-readable name for UI
    ///   - branch: Current git branch (optional)
    ///   - bookmark: Security-scoped bookmark data (optional)
    ///   - createdAt: Creation timestamp (defaults to now)
    public init(
        id: String,
        path: String,
        displayName: String,
        branch: String? = nil,
        bookmark: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.branch = branch
        self.bookmark = bookmark
        self.createdAt = createdAt
    }
}

// MARK: - CustomStringConvertible

extension ActiveProjectContext: CustomStringConvertible {
    public var description: String {
        let branchInfo = branch.map { " (\($0))" } ?? ""
        return "ActiveProjectContext(id: \(id), name: \(displayName)\(branchInfo), path: \(path))"
    }
}

// MARK: - Convenience Accessors

extension ActiveProjectContext {
    /// The project root as a URL.
    public var projectURL: URL {
        URL(fileURLWithPath: path)
    }

    /// Whether this project is a git repository.
    public var isGitRepository: Bool {
        branch != nil
    }
}
