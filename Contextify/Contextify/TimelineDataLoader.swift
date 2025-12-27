//
//  TimelineDataLoader.swift
//  Contextify
//
//  Background actor for database queries and feed loading.
//  Extracted from ConversationMonitor to reduce god object complexity.
//
//  Phase 2: Converted from @MainActor class to background actor.
//  Owns cursor, seen IDs, decoration data, and refresh tracking.
//

import Foundation
import OSLog
import ContextifyCore

// MARK: - Decoration Snapshot

/// Immutable snapshot of decoration data for entry mapping
public struct DecorationSnapshot: Sendable {
    public let spawnedAgentsLookup: [String: TranscriptOrchestrator.AgentDecorationInfo]
    public let contextifyEntryIds: Set<String>
    public let contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo]

    public nonisolated init(
        spawnedAgentsLookup: [String: TranscriptOrchestrator.AgentDecorationInfo] = [:],
        contextifyEntryIds: Set<String> = [],
        contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo] = [:]
    ) {
        self.spawnedAgentsLookup = spawnedAgentsLookup
        self.contextifyEntryIds = contextifyEntryIds
        self.contextifyEntryInfo = contextifyEntryInfo
    }

    public nonisolated static var empty: DecorationSnapshot { DecorationSnapshot() }
}

// MARK: - Feed Load Result

/// Result of loading timeline feed from database
public struct FeedLoadResult: Sendable {
    public let entries: [(TranscriptEntry, TimelineCache?)]
    public let transcriptPaths: [String: String]
    public let newestCursor: EntryCursor?
    public let decoration: DecorationSnapshot

    public nonisolated init(
        entries: [(TranscriptEntry, TimelineCache?)],
        transcriptPaths: [String: String],
        newestCursor: EntryCursor?,
        decoration: DecorationSnapshot
    ) {
        self.entries = entries
        self.transcriptPaths = transcriptPaths
        self.newestCursor = newestCursor
        self.decoration = decoration
    }
}

/// Result of incremental update processing
public struct IncrementalUpdateResult: Sendable {
    public let newEntries: [TranscriptEntry]
    public let transcriptPaths: [String: String]
    public let updatedCursor: EntryCursor?
    public let decoration: DecorationSnapshot

    public nonisolated init(
        newEntries: [TranscriptEntry],
        transcriptPaths: [String: String],
        updatedCursor: EntryCursor?,
        decoration: DecorationSnapshot
    ) {
        self.newEntries = newEntries
        self.transcriptPaths = transcriptPaths
        self.updatedCursor = updatedCursor
        self.decoration = decoration
    }
}

// MARK: - Timeline Data Loader

/// Background actor for database queries and feed loading.
/// Owns cursor, seen IDs, decoration data, and refresh tracking.
/// ConversationMonitor awaits loader calls from off-main tasks.
public actor TimelineDataLoader {
    private let log = Logger(subsystem: "dev.contextify.timeline", category: "TimelineDataLoader")
    private let orchestrator: TranscriptOrchestrator

    // Cursor state (project-scoped)
    public private(set) var lastSeenCursor: EntryCursor?
    private var currentProjectId: String?

    // Seen entry tracking (for deduplication)
    private var seenEntryIDs = Set<String>()

    // Decoration data (agent types, Contextify entries)
    private var spawnedAgentsLookup: [String: TranscriptOrchestrator.AgentDecorationInfo] = [:]
    private var contextifyEntryIds: Set<String> = Set()
    private var contextifyEntryInfo: [String: TranscriptOrchestrator.ContextifyEntryInfo] = [:]

    // Refresh tracking (diagnostics)
    private var refreshHistory: [(trigger: String, timestamp: Date)] = []

    public init(orchestrator: TranscriptOrchestrator) {
        self.orchestrator = orchestrator
    }

    // MARK: - Cursor Persistence

    /// Load persisted cursor for project from UserDefaults
    public func loadCursor(projectId: String) {
        currentProjectId = projectId
        let key = "dev.contextify.cursor.\(projectId.sha1Hex())"
        guard let data = UserDefaults.standard.data(forKey: key) else {
            log.debug("[CURSOR] No persisted cursor for project \(projectId, privacy: .public)")
            return
        }
        if let cursor = try? JSONDecoder().decode(EntryCursor.self, from: data) {
            lastSeenCursor = cursor
            log.debug("[CURSOR] Loaded persisted cursor for project \(projectId, privacy: .public): \(cursor.id, privacy: .public)")
        }
    }

    /// Save current cursor to UserDefaults (best-effort, actor-internal)
    private func saveCursor() {
        guard let projectId = currentProjectId, let cursor = lastSeenCursor else { return }
        let key = "dev.contextify.cursor.\(projectId.sha1Hex())"
        guard let data = try? JSONEncoder().encode(cursor) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Update cursor from entry and persist
    public func updateCursor(from entry: TranscriptEntry) {
        lastSeenCursor = EntryCursor(from: entry)
        saveCursor()
    }

    /// Set cursor directly and persist (for backward compat during wiring)
    public func setCursor(_ cursor: EntryCursor) {
        lastSeenCursor = cursor
        saveCursor()
    }

    // MARK: - Seen Entry Tracking

    /// Check if entry has been seen (for deduplication)
    public func hasSeenEntry(_ id: String) -> Bool {
        seenEntryIDs.contains(id)
    }

    /// Filter entries to only those not yet seen, and mark them as seen
    public func filterAndMarkNewEntries(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        var newEntries: [TranscriptEntry] = []
        for entry in entries {
            if !seenEntryIDs.contains(entry.id) {
                seenEntryIDs.insert(entry.id)
                newEntries.append(entry)
            }
        }
        return newEntries
    }

    /// Prune seen IDs to prevent unbounded growth
    public func pruneSeenIDsIfNeeded(currentEntryIDs: [String], maxEntries: Int) {
        let cap = maxEntries * 2
        if seenEntryIDs.count > cap {
            seenEntryIDs = Set(currentEntryIDs)
            log.debug("[SEEN-IDS] Pruned to \(self.seenEntryIDs.count, privacy: .public) entries (cap: \(cap, privacy: .public))")
        }
    }

    // MARK: - Decoration Data

    /// Refresh decoration lookup tables for the current project
    private func refreshDecorationData(projectId: String) {
        do {
            spawnedAgentsLookup = try orchestrator.getSpawnedAgentEntries(projectId: projectId)
            contextifyEntryIds = try orchestrator.getContextifyEntryIds(projectId: projectId)
            contextifyEntryInfo = try orchestrator.getContextifyEntryInfo(projectId: projectId)
            if !spawnedAgentsLookup.isEmpty || !contextifyEntryIds.isEmpty {
                log.debug("[DECORATION] Loaded: \(self.spawnedAgentsLookup.count, privacy: .public) agents, \(self.contextifyEntryIds.count, privacy: .public) contextify entries")
            }
        } catch {
            log.warning("[DECORATION] Failed to load: \(error.localizedDescription, privacy: .public)")
            spawnedAgentsLookup.removeAll()
            contextifyEntryIds.removeAll()
            contextifyEntryInfo.removeAll()
        }
    }

    /// Create immutable snapshot of current decoration data
    private func decorationSnapshot() -> DecorationSnapshot {
        DecorationSnapshot(
            spawnedAgentsLookup: spawnedAgentsLookup,
            contextifyEntryIds: contextifyEntryIds,
            contextifyEntryInfo: contextifyEntryInfo
        )
    }

    // MARK: - Reset

    private func resetState(clearCursor: Bool) {
        seenEntryIDs.removeAll(keepingCapacity: false)
        spawnedAgentsLookup.removeAll()
        contextifyEntryIds.removeAll()
        contextifyEntryInfo.removeAll()
        refreshHistory.removeAll()

        if clearCursor {
            lastSeenCursor = nil
            currentProjectId = nil
        }
    }

    /// Reset loader state for project/session change
    /// - Parameter clearCursor: true for project change (clear cursor), false for session change (keep cursor)
    public func reset(clearCursor: Bool, reason: String) {
        log.info("[RESET] reason=\(reason, privacy: .public) clearCursor=\(clearCursor, privacy: .public)")
        resetState(clearCursor: clearCursor)
    }

    /// Reset loader state only if it is still associated with the expected project.
    /// Used to avoid racing a late reset against a new project after a rapid switch.
    public func resetIfProjectMatches(_ expectedProjectId: String?, clearCursor: Bool, reason: String) {
        if let expectedProjectId,
           let currentProjectId,
           currentProjectId != expectedProjectId {
            log.debug("[RESET-SKIP] reason=\(reason, privacy: .public) expected=\(expectedProjectId, privacy: .public) current=\(currentProjectId, privacy: .public)")
            return
        }
        log.info("[RESET] reason=\(reason, privacy: .public) clearCursor=\(clearCursor, privacy: .public)")
        resetState(clearCursor: clearCursor)
    }

    // MARK: - Feed Loading

    /// Load recent feed from database
    public func loadFeed(
        projectId: String,
        limit: Int,
        generatorSignature: String
    ) throws -> FeedLoadResult {
        // Cancellation checkpoint before DB work
        try Task.checkCancellation()

        log.info("[FEED-LOAD] Loading for project: \(projectId, privacy: .public) limit: \(limit, privacy: .public)")
        currentProjectId = projectId

        let feed = try orchestrator.getRecentFeed(
            forProject: projectId,
            limit: limit,
            generatorSignature: generatorSignature
        )

        // Cancellation checkpoint after main query
        try Task.checkCancellation()

        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let transcriptPaths = Dictionary(uniqueKeysWithValues: transcripts.map { ($0.id, $0.filePath) })

        // Refresh decoration data
        refreshDecorationData(projectId: projectId)

        // Track seen IDs (full load replaces the set)
        seenEntryIDs.removeAll(keepingCapacity: true)
        for (entry, _) in feed {
            seenEntryIDs.insert(entry.id)
        }

        // Update cursor from newest entry
        let newestCursor: EntryCursor?
        if let newestEntry = feed.last?.0 {
            newestCursor = EntryCursor(from: newestEntry)
            lastSeenCursor = newestCursor
            saveCursor()
        } else {
            newestCursor = nil
        }

        log.info("[FEED-LOAD] Loaded \(feed.count, privacy: .public) entries, seenIDs=\(self.seenEntryIDs.count, privacy: .public)")

        return FeedLoadResult(
            entries: feed,
            transcriptPaths: transcriptPaths,
            newestCursor: newestCursor,
            decoration: decorationSnapshot()
        )
    }

    /// Process incremental update using cursor pagination
    /// Returns only entries not already seen (dedup handled by loader)
    public func processIncremental(
        projectId: String
    ) throws -> IncrementalUpdateResult {
        // Cancellation checkpoint
        try Task.checkCancellation()

        if let currentProjectId, currentProjectId != projectId {
            log.warning("[INCR-UPDATE] Project mismatch (current=\(currentProjectId, privacy: .public), requested=\(projectId, privacy: .public)); resetting state and forcing reload")
            resetState(clearCursor: true)
            return IncrementalUpdateResult(
                newEntries: [],
                transcriptPaths: [:],
                updatedCursor: nil,
                decoration: DecorationSnapshot.empty
            )
        }
        currentProjectId = projectId

        guard let cursor = lastSeenCursor else {
            log.debug("[INCR-UPDATE] No cursor available")
            return IncrementalUpdateResult(
                newEntries: [],
                transcriptPaths: [:],
                updatedCursor: nil,
                decoration: decorationSnapshot()
            )
        }

        log.info("[INCR-UPDATE] Fetching entries after cursor for project: \(projectId, privacy: .public)")

        let rawEntries = try orchestrator.getEntriesAfterCursor(
            projectId: projectId,
            after: cursor
        )

        // Cancellation checkpoint after query
        try Task.checkCancellation()

        // Filter to only unseen entries (loader owns dedup)
        let newEntries = filterAndMarkNewEntries(rawEntries)

        guard !newEntries.isEmpty else {
            log.debug("[INCR-UPDATE] No new unseen entries")
            return IncrementalUpdateResult(
                newEntries: [],
                transcriptPaths: [:],
                updatedCursor: nil,
                decoration: decorationSnapshot()
            )
        }

        log.info("[INCR-UPDATE] Found \(newEntries.count, privacy: .public) new entries (filtered from \(rawEntries.count, privacy: .public))")

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
            saveCursor()
        } else {
            updatedCursor = nil
        }

        return IncrementalUpdateResult(
            newEntries: newEntries,
            transcriptPaths: transcriptPaths,
            updatedCursor: updatedCursor,
            decoration: decorationSnapshot()
        )
    }

    // MARK: - Session Loading

    /// Load all sessions from database for transcripts
    func loadAllSessions(projectId: String) throws -> [TranscriptSession] {
        try Task.checkCancellation()

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

        log.info("[SESSIONS] Loaded \(sessions.count, privacy: .public) sessions")
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

            let lastActivityTimestamp = latestTimestamps[transcript.id] ?? transcript.updatedAt
            let lastActivity = Date(timeIntervalSince1970: TimeInterval(lastActivityTimestamp))
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
