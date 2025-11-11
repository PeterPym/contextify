import Foundation
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "BookmarkStore")

/// Persists security-scoped bookmark authorizations to disk as JSON.
/// Thread-safe actor for concurrent access from UI and background tasks.
public actor BookmarkStore {
    /// Container for all source authorizations
    private struct Container: Codable {
        var version: Int = 1
        var authorizations: [SourceID: SourceAuthorization]
        var lastModified: Date

        init(authorizations: [SourceID: SourceAuthorization] = [:]) {
            self.authorizations = authorizations
            self.lastModified = Date()
        }
    }

    private let fileURL: URL
    private var container: Container

    /// Create a bookmark store at the specified file URL.
    /// If the file exists, it will be loaded. Otherwise, an empty store is created.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.container = Container()

        // Attempt to load existing data
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let loaded = try JSONDecoder().decode(Container.self, from: data)
                self.container = loaded
                log.info("Loaded \(loaded.authorizations.count) bookmark(s) from \(fileURL.path)")
            } catch {
                log.error("Failed to load bookmarks from \(fileURL.path): \(error.localizedDescription)")
                // Continue with empty container
            }
        } else {
            log.info("No existing bookmarks file at \(fileURL.path), starting fresh")
        }
    }

    /// Convenience initializer using default location.
    /// For sandboxed builds: ~/Library/Containers/<BID>/Data/Library/Application Support/Contextify/bookmarks.json
    /// For unsandboxed builds: ~/Library/Application Support/Contextify/bookmarks.json
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let contextifyDir = appSupport.appendingPathComponent("Contextify", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: contextifyDir,
            withIntermediateDirectories: true
        )

        let fileURL = contextifyDir.appendingPathComponent("bookmarks.json")
        self.init(fileURL: fileURL)
    }

    /// Retrieve authorization for a specific source
    public func authorization(for id: SourceID) -> SourceAuthorization? {
        container.authorizations[id]
    }

    /// Retrieve all authorizations
    public func allAuthorizations() -> [SourceAuthorization] {
        Array(container.authorizations.values)
    }

    /// Save or update an authorization
    public func save(_ authorization: SourceAuthorization) throws {
        container.authorizations[authorization.id] = authorization
        container.lastModified = Date()
        try persist()
        log.info("Saved authorization for \(authorization.id.rawValue): status=\(authorization.status.rawValue)")
    }

    /// Remove an authorization
    public func remove(_ id: SourceID) throws {
        container.authorizations.removeValue(forKey: id)
        container.lastModified = Date()
        try persist()
        log.info("Removed authorization for \(id.rawValue)")
    }

    /// Clear all authorizations
    public func clear() throws {
        container.authorizations.removeAll()
        container.lastModified = Date()
        try persist()
        log.info("Cleared all authorizations")
    }

    /// Check if any sources are authorized
    public func hasAnyAuthorizations() -> Bool {
        container.authorizations.values.contains { $0.status == .authorized }
    }

    /// Count of authorized sources
    public func authorizedCount() -> Int {
        container.authorizations.values.filter { $0.status == .authorized }.count
    }

    // MARK: - Private

    private func persist() throws {
        // Ensure parent directory exists
        let parentDir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(container)
        try data.write(to: fileURL, options: .atomic)
    }
}
