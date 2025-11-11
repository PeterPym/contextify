import Foundation

/// Identifies a transcript source that requires folder access authorization.
public enum SourceID: String, Codable, Sendable, CaseIterable {
    case claude = "claude"
    case codex = "codex"

    /// Human-readable display name for UI
    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// Default directory path relative to user's home directory
    public var defaultPath: String {
        switch self {
        case .claude: return ".claude/projects"
        case .codex: return ".codex/sessions"
        }
    }

    /// Full URL to default location (may not exist)
    public var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(defaultPath)
    }
}

/// Authorization status for a transcript source folder.
public enum AuthorizationStatus: String, Codable, Sendable {
    /// User has granted access and bookmark is valid
    case authorized

    /// User has not granted access or explicitly revoked it
    case notAuthorized

    /// Bookmark exists but cannot be resolved (folder moved/deleted)
    case broken
}

/// Represents authorization state for accessing a transcript source folder.
/// Uses security-scoped bookmarks for persistent access in sandboxed builds.
public struct SourceAuthorization: Equatable, Codable, Sendable {
    /// Source identifier
    public let id: SourceID

    /// Security-scoped bookmark data (nil if not authorized)
    public var bookmarkData: Data?

    /// User-friendly display name or last known path
    public var displayName: String?

    /// Last successfully resolved URL (cached for UI display)
    public var lastResolvedURL: URL?

    /// Current authorization status
    public var status: AuthorizationStatus

    /// Timestamp when authorization was last updated
    public var lastUpdated: Date

    public init(
        id: SourceID,
        bookmarkData: Data? = nil,
        displayName: String? = nil,
        lastResolvedURL: URL? = nil,
        status: AuthorizationStatus = .notAuthorized,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.bookmarkData = bookmarkData
        self.displayName = displayName
        self.lastResolvedURL = lastResolvedURL
        self.status = status
        self.lastUpdated = lastUpdated
    }

    /// Create an authorized instance from a URL with a new security-scoped bookmark
    public static func authorized(
        id: SourceID,
        url: URL,
        bookmarkData: Data
    ) -> SourceAuthorization {
        SourceAuthorization(
            id: id,
            bookmarkData: bookmarkData,
            displayName: url.path,
            lastResolvedURL: url,
            status: .authorized,
            lastUpdated: Date()
        )
    }

    /// Mark as broken (bookmark no longer resolves)
    public mutating func markBroken() {
        status = .broken
        lastUpdated = Date()
    }

    /// Mark as not authorized (user revoked or never granted)
    public mutating func markNotAuthorized() {
        status = .notAuthorized
        bookmarkData = nil
        lastResolvedURL = nil
        lastUpdated = Date()
    }

    /// Update with refreshed bookmark data and URL
    public mutating func refresh(url: URL, bookmarkData: Data) {
        self.bookmarkData = bookmarkData
        self.lastResolvedURL = url
        self.displayName = url.path
        self.status = .authorized
        self.lastUpdated = Date()
    }
}

/// Result of resolving a security-scoped bookmark
public struct URLResolution: Sendable {
    /// The resolved URL
    public let url: URL

    /// Whether the bookmark data is stale and should be refreshed
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}
