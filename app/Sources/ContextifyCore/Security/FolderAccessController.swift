import Foundation
import AppKit
import OSLog

private let log = Logger(subsystem: "dev.contextify", category: "FolderAccess")

/// Errors that can occur during folder access operations
public enum FolderAccessError: Error, LocalizedError {
    case bookmarkCreationFailed(URL)
    case bookmarkResolutionFailed
    case securityScopeAccessDenied(URL)
    case userCancelled
    case staleBookmarkRefreshFailed(URL)
    case noTranscriptsFound(URL, SourceID)

    public var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed(let url):
            return "Failed to create security-scoped bookmark for \(url.path)"
        case .bookmarkResolutionFailed:
            return "Failed to resolve security-scoped bookmark"
        case .securityScopeAccessDenied(let url):
            return "Access to security-scoped resource denied: \(url.path)"
        case .userCancelled:
            return "User cancelled folder selection"
        case .staleBookmarkRefreshFailed(let url):
            return "Failed to refresh stale bookmark for \(url.path)"
        case .noTranscriptsFound(let url, let source):
            return "No \(source.displayName) transcripts found in \(url.lastPathComponent). Please select the correct folder (usually \(source.defaultPath))."
        }
    }
}

/// Manages security-scoped bookmark creation, resolution, and folder access authorization.
/// Thread-safe actor for concurrent access from UI and background operations.
@MainActor
public final class FolderAccessController: ObservableObject {
    private let store: BookmarkStore

    public init(store: BookmarkStore) {
        self.store = store
    }

    public convenience init() {
        self.init(store: BookmarkStore())
    }

    // MARK: - Public API

    /// Request folder access for one or more sources via NSOpenPanel.
    /// Returns updated authorizations for all requested sources.
    @MainActor
    public func requestAccess(for sources: [SourceID]) async throws -> [SourceAuthorization] {
        guard !sources.isEmpty else { return [] }

        log.info("Requesting access for sources: \(sources.map(\.rawValue).joined(separator: ", "))")

        // Configure open panel
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"

        // Set message based on sources requested
        if sources.count == 1 {
            let source = sources[0]
            panel.message = "Choose your \(source.displayName) transcripts folder"
            panel.directoryURL = source.defaultURL
        } else {
            panel.message = "Choose your transcript folders (you can select multiple)"
        }

        // Show panel and wait for user response
        let response = panel.runModal()
        guard response == .OK else {
            log.info("User cancelled folder selection")
            throw FolderAccessError.userCancelled
        }

        // Process selected URLs
        var results: [SourceAuthorization] = []

        for url in panel.urls {
            log.info("User selected: \(url.path)")

            // Try to match URL to requested sources
            guard let matchedSource = matchURLToSource(url, candidates: sources) else {
                log.warning("Selected URL does not match any requested sources: \(url.path)")
                continue
            }

            // Validate that folder contains transcripts
            guard validateTranscripts(in: url, for: matchedSource) else {
                log.error("No transcripts found in selected folder: \(url.path)")
                throw FolderAccessError.noTranscriptsFound(url, matchedSource)
            }

            do {
                let auth = try await createAuthorization(for: matchedSource, url: url)
                results.append(auth)
                log.info("Created authorization: source=\(matchedSource.rawValue) url=\(url.path)")
            } catch {
                log.error("Failed to create authorization for \(matchedSource.rawValue): \(error.localizedDescription)")
                throw error
            }
        }

        return results
    }

    /// Resolve a security-scoped bookmark to a URL.
    /// Returns the resolved URL and whether the bookmark is stale.
    /// If stale, caller should refresh the bookmark via `refreshBookmark`.
    public func resolve(_ authorization: SourceAuthorization) async throws -> URLResolution {
        guard let bookmarkData = authorization.bookmarkData else {
            throw FolderAccessError.bookmarkResolutionFailed
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        log.info("Resolved bookmark: source=\(authorization.id.rawValue) url=\(url.path) stale=\(isStale)")

        return URLResolution(url: url, isStale: isStale)
    }

    /// Execute an operation with security-scoped access to the authorized folder.
    /// Automatically starts and stops the security scope.
    public func withAccess<T>(
        _ authorization: SourceAuthorization,
        _ operation: @Sendable (URL) throws -> T
    ) async throws -> T {
        let resolution = try await resolve(authorization)

        guard resolution.url.startAccessingSecurityScopedResource() else {
            log.error("Failed to start accessing security-scoped resource: \(resolution.url.path)")
            throw FolderAccessError.securityScopeAccessDenied(resolution.url)
        }

        defer {
            resolution.url.stopAccessingSecurityScopedResource()
        }

        // If stale, try to refresh in background (don't block operation)
        if resolution.isStale {
            log.warning("Bookmark is stale, will attempt refresh: \(resolution.url.path)")
            Task {
                do {
                    try await refreshBookmark(for: authorization.id, url: resolution.url)
                } catch {
                    log.error("Failed to refresh stale bookmark: \(error.localizedDescription)")
                }
            }
        }

        return try operation(resolution.url)
    }

    /// Refresh a stale bookmark by creating a new one from the resolved URL.
    public func refreshBookmark(for sourceID: SourceID, url: URL) async throws {
        log.info("Refreshing bookmark for \(sourceID.rawValue): \(url.path)")

        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        guard var authorization = await store.authorization(for: sourceID) else {
            log.error("Cannot refresh bookmark: authorization not found for \(sourceID.rawValue)")
            return
        }

        authorization.refresh(url: url, bookmarkData: bookmarkData)
        try await store.save(authorization)

        log.info("Successfully refreshed bookmark for \(sourceID.rawValue)")
    }

    /// Remove authorization for a source.
    public func forget(_ sourceID: SourceID) async throws {
        try await store.remove(sourceID)
        log.info("Removed authorization for \(sourceID.rawValue)")
    }

    /// Get current authorization for a source.
    public func authorization(for sourceID: SourceID) async -> SourceAuthorization? {
        await store.authorization(for: sourceID)
    }

    /// Get all authorizations.
    public func allAuthorizations() async -> [SourceAuthorization] {
        await store.allAuthorizations()
    }

    /// Check if any sources are currently authorized.
    public func hasAnyAuthorizations() async -> Bool {
        await store.hasAnyAuthorizations()
    }

    // MARK: - Private Helpers

    private func createAuthorization(for source: SourceID, url: URL) async throws -> SourceAuthorization {
        // Create security-scoped bookmark
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let authorization = SourceAuthorization.authorized(
            id: source,
            url: url,
            bookmarkData: bookmarkData
        )

        // Persist immediately
        try await store.save(authorization)

        return authorization
    }

    /// Match a selected URL to a source based on path heuristics.
    /// Looks for ".claude" or ".codex" in the path.
    private func matchURLToSource(_ url: URL, candidates: [SourceID]) -> SourceID? {
        let path = url.path.lowercased()

        // Try exact match first
        for source in candidates {
            if path.contains(source.defaultPath) {
                return source
            }
        }

        // Try partial match (e.g., path contains "claude" or "codex")
        for source in candidates {
            if path.contains(source.rawValue) {
                return source
            }
        }

        // If only one candidate, assume it's the right one
        if candidates.count == 1 {
            return candidates[0]
        }

        return nil
    }

    /// Validate that a folder contains transcripts for the given source.
    /// Returns true if transcripts are found, false otherwise.
    private func validateTranscripts(in url: URL, for source: SourceID) -> Bool {
        let fm = FileManager.default

        switch source {
        case .claude:
            // Claude Code structure: .claude/projects/<project-hash>/<session>.jsonl
            // Check if url contains project subdirectories with .jsonl files
            guard let subdirs = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                log.debug("Cannot read directory: \(url.path)")
                return false
            }

            // Check if any subdirectory contains .jsonl files
            for subdir in subdirs {
                guard (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }

                if let files = try? fm.contentsOfDirectory(
                    at: subdir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ), files.contains(where: { $0.pathExtension == "jsonl" }) {
                    log.info("Found Claude Code transcripts in: \(subdir.lastPathComponent)")
                    return true
                }
            }

            log.warning("No Claude Code transcripts found in: \(url.path)")
            return false

        case .codex:
            // Codex structure: .codex/sessions/<session>.jsonl (flat)
            // Check if url contains .jsonl files directly
            guard let files = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                log.debug("Cannot read directory: \(url.path)")
                return false
            }

            let hasTranscripts = files.contains(where: { $0.pathExtension == "jsonl" })
            if hasTranscripts {
                log.info("Found Codex transcripts in: \(url.path)")
            } else {
                log.warning("No Codex transcripts found in: \(url.path)")
            }
            return hasTranscripts
        }
    }
}
