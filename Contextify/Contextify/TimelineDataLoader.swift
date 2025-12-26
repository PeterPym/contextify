//
//  TimelineDataLoader.swift
//  Contextify
//
//  Extracted from ConversationMonitor - handles database queries and feed loading
//

import Foundation
import OSLog
import ContextifyCore

// MARK: - Cursor Persistence Actor

/// Off-main-thread cursor persistence to avoid UI jank
private actor CursorPersistenceActor {
    func load(projectId: String) -> EntryCursor? {
        let key = "dev.contextify.cursor.\(projectId.sha1Hex())"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EntryCursor.self, from: data)
    }

    func save(projectId: String, cursor: EntryCursor) {
        let key = "dev.contextify.cursor.\(projectId.sha1Hex())"
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Feed Load Result

/// Result of loading timeline feed from database
public struct FeedLoadResult: Sendable {
    public let entries: [(TranscriptEntry, TimelineCache?)]
    public let transcriptPaths: [String: String]
    public let newestCursor: EntryCursor?

    public init(
        entries: [(TranscriptEntry, TimelineCache?)],
        transcriptPaths: [String: String],
        newestCursor: EntryCursor?
    ) {
        self.entries = entries
        self.transcriptPaths = transcriptPaths
        self.newestCursor = newestCursor
    }
}

/// Result of incremental update processing
public struct IncrementalUpdateResult: Sendable {
    public let newEntries: [TranscriptEntry]
    public let transcriptPaths: [String: String]
    public let updatedCursor: EntryCursor?

    public init(
        newEntries: [TranscriptEntry],
        transcriptPaths: [String: String],
        updatedCursor: EntryCursor?
    ) {
        self.newEntries = newEntries
        self.transcriptPaths = transcriptPaths
        self.updatedCursor = updatedCursor
    }
}

// MARK: - Timeline Data Loader

/// Handles database queries and feed loading for the timeline
/// Extracted from ConversationMonitor to reduce god object complexity
@MainActor
public final class TimelineDataLoader {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "TimelineDataLoader")
    private let orchestrator: TranscriptOrchestrator
    private let cursorPersistence = CursorPersistenceActor()

    // State
    public private(set) var lastSeenCursor: EntryCursor?
    private var seenEntryIDs = Set<String>()

    // Decoration data (agent types, Contextify entries)
    private(set) var spawnedAgentsLookup: [String: TranscriptOrchestrator.AgentDecorationInfo] = [:]
    private(set) var contextifyEntryIds: Set<String> = Set()
    private(set) var contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo] = [:]

    // Refresh tracking
    private var refreshHistory: [(trigger: String, timestamp: Date)] = []
    private var lastProgressRefreshTime: Date?

    public init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
    }

    // MARK: - Cursor Persistence

    /// Load persisted cursor for project from UserDefaults
    public func loadCursor(projectId: String) async {
        if let cursor = await cursorPersistence.load(projectId: projectId) {
            lastSeenCursor = cursor
            log.debug("Loaded persisted cursor for project \(projectId, privacy: .public): \(cursor.id, privacy: .public)")
        }
    }

    /// Save current cursor to UserDefaults for restart safety
    public func saveCursor(projectId: String) {
        guard let cursor = lastSeenCursor else { return }
        Task.detached { [cursor, weak self] in
            await self?.cursorPersistence.save(projectId: projectId, cursor: cursor)
        }
    }

    /// Update cursor from entry
    public func updateCursor(from entry: TranscriptEntry, projectId: String) {
        lastSeenCursor = EntryCursor(from: entry)
        saveCursor(projectId: projectId)
    }

    // MARK: - Seen Entry Tracking

    /// Check if entry has been seen (for deduplication)
    public func hasSeenEntry(_ id: String) -> Bool {
        seenEntryIDs.contains(id)
    }

    /// Mark entry as seen
    public func markEntrySeen(_ id: String) {
        seenEntryIDs.insert(id)
    }

    /// Clear all seen entries
    public func clearSeenEntries() {
        seenEntryIDs.removeAll(keepingCapacity: false)
    }

    /// Prune seen IDs to prevent unbounded growth
    public func pruneSeenIDsIfNeeded(currentEntryIDs: [String], maxEntries: Int) {
        let cap = maxEntries * 2
        if seenEntryIDs.count > cap {
            seenEntryIDs = Set(currentEntryIDs)
        }
    }

    // MARK: - Decoration Data

    /// Refresh decoration lookup tables for the current project
    public func refreshDecorationData(projectId: String) {
        do {
            spawnedAgentsLookup = try orchestrator.getSpawnedAgentEntries(projectId: projectId)
            contextifyEntryIds = try orchestrator.getContextifyEntryIds(projectId: projectId)
            contextifyEntryInfo = try orchestrator.getContextifyEntryInfo(projectId: projectId)
            if !spawnedAgentsLookup.isEmpty || !contextifyEntryIds.isEmpty {
                log.debug("[DECORATION] Loaded decoration data: \(self.spawnedAgentsLookup.count, privacy: .public) agents, \(self.contextifyEntryIds.count, privacy: .public) contextify entries")
            }
        } catch {
            log.warning("[DECORATION] Failed to load decoration data: \(error.localizedDescription, privacy: .public)")
            spawnedAgentsLookup.removeAll()
            contextifyEntryIds.removeAll()
            contextifyEntryInfo.removeAll()
        }
    }

    // MARK: - Feed Loading

    /// Load recent feed from database
    public func loadFeed(
        projectId: String,
        limit: Int,
        generatorSignature: String
    ) async throws -> FeedLoadResult {
        log.info("[FEED-LOAD] Loading feed for project: \(projectId, privacy: .public) limit: \(limit, privacy: .public)")

        let feed = try orchestrator.getRecentFeed(
            forProject: projectId,
            limit: limit,
            generatorSignature: generatorSignature
        )

        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let transcriptPaths = Dictionary(uniqueKeysWithValues: transcripts.map { ($0.id, $0.filePath) })

        // Refresh decoration data
        refreshDecorationData(projectId: projectId)

        // Track seen IDs
        seenEntryIDs.removeAll(keepingCapacity: true)
        for (entry, _) in feed {
            seenEntryIDs.insert(entry.id)
        }

        // Update cursor from newest entry
        let newestCursor: EntryCursor?
        if let newestEntry = feed.last?.0 {
            newestCursor = EntryCursor(from: newestEntry)
            lastSeenCursor = newestCursor
            saveCursor(projectId: projectId)
        } else {
            newestCursor = nil
        }

        log.info("[FEED-LOAD] Loaded \(feed.count, privacy: .public) entries")

        return FeedLoadResult(
            entries: feed,
            transcriptPaths: transcriptPaths,
            newestCursor: newestCursor
        )
    }

    /// Process incremental update using cursor pagination
    public func processIncremental(
        projectId: String,
        cursor: EntryCursor
    ) async throws -> IncrementalUpdateResult {
        log.info("[INCR-UPDATE] Fetching entries after cursor for project: \(projectId, privacy: .public)")

        let newEntries = try orchestrator.getEntriesAfterCursor(
            projectId: projectId,
            after: cursor
        )

        guard !newEntries.isEmpty else {
            log.debug("[INCR-UPDATE] No new entries")
            return IncrementalUpdateResult(
                newEntries: [],
                transcriptPaths: [:],
                updatedCursor: nil
            )
        }

        log.info("[INCR-UPDATE] Found \(newEntries.count, privacy: .public) new entries")

        // Build transcript path lookup
        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let transcriptPaths = Dictionary(uniqueKeysWithValues: transcripts.map { ($0.id, $0.filePath) })

        // Refresh decoration data
        refreshDecorationData(projectId: projectId)

        // Update cursor to latest entry
        let updatedCursor: EntryCursor?
        if let latestNew = newEntries.max(by: { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }) {
            updatedCursor = EntryCursor(from: latestNew)
            lastSeenCursor = updatedCursor
            saveCursor(projectId: projectId)
        } else {
            updatedCursor = nil
        }

        return IncrementalUpdateResult(
            newEntries: newEntries,
            transcriptPaths: transcriptPaths,
            updatedCursor: updatedCursor
        )
    }

    // MARK: - Session Loading

    /// Load all sessions from database for transcripts
    func loadAllSessions(projectId: String) async throws -> [TranscriptSession] {
        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let latestTimestamps = try orchestrator.latestTimestampsByTranscript(projectId: projectId)

        // Fetch entry counts for all transcripts
        var entryCounts: [String: Int] = [:]
        for transcript in transcripts {
            if let count = try? orchestrator.getEntryCount(transcriptId: transcript.id) {
                entryCounts[transcript.id] = count
            }
        }

        let sessions = Self.mapTranscriptsToSessions(
            transcripts: transcripts,
            latestTimestamps: latestTimestamps,
            entryCounts: entryCounts
        )

        log.info("Loaded \(sessions.count) sessions from database")
        return sessions
    }

    /// Map transcripts to session objects
    nonisolated static func mapTranscriptsToSessions(
        transcripts: [Transcript],
        latestTimestamps: [String: Int],
        entryCounts: [String: Int]
    ) -> [TranscriptSession] {
        return transcripts.compactMap { transcript in
            let fileURL = URL(fileURLWithPath: transcript.filePath)
            let provider: TimelineSourceContext.Provider
            switch transcript.provider {
            case "claude.code": provider = .claudeCode
            case "codex.cli": provider = .codexCLI
            default: provider = .other
            }

            // Use latest conversation timestamp if available, otherwise fall back to file modified time
            let lastActivityTimestamp = latestTimestamps[transcript.id] ?? transcript.updatedAt
            let lastActivity = Date(timeIntervalSince1970: TimeInterval(lastActivityTimestamp))

            // Get entry count (defaults to 0 if not found)
            let entryCount = entryCounts[transcript.id] ?? 0

            return TranscriptSession(
                provider: provider,
                identifier: transcript.id,
                fileURL: fileURL,
                lastActivity: lastActivity,
                entryCount: entryCount
            )
        }.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Cache Operations

    /// Get cached timeline entry
    public func getCachedTimeline(key: CacheKey) throws -> TimelineCache? {
        try orchestrator.getCachedTimeline(key: key)
    }

    /// Get multiple cached timeline entries
    public func getCachedTimelineMany(keys: [CacheKey]) throws -> [CacheKey: TimelineCache] {
        try orchestrator.getCachedTimelineMany(keys: keys)
    }

    /// Get cached entries with signature verification
    public func getCachedTimelineManyWithSignature(
        keys: [CacheKey],
        generatorSignature: String
    ) throws -> [CacheKey: TimelineCache] {
        try orchestrator.getCachedTimelineManyWithSignature(
            keys: keys,
            generatorSignature: generatorSignature
        )
    }

    // MARK: - Refresh Tracking

    /// Record refresh for diagnostics
    public func recordRefresh(trigger: String) {
        refreshHistory.append((trigger, Date()))
        // Keep last 100
        if refreshHistory.count > 100 {
            refreshHistory.removeFirst()
        }
        // Log warning if >5 refreshes in 5 seconds
        let recent = refreshHistory.filter { Date().timeIntervalSince($0.timestamp) < 5 }
        if recent.count > 5 {
            log.warning("[REFRESH-RATE] High refresh rate: \(recent.count, privacy: .public) refreshes in 5s")
        }
    }
}

// NOTE: sha1Hex() extension is defined in ConversationMonitor.swift
