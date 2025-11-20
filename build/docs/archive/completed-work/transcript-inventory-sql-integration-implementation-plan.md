# Transcripts SQL Integration - Implementation Plan

**Date**: 2025-10-18
**Branch**: `feature/transcript-inventory-db-integration`
**Status**: Approved for Implementation
**Reviewers**: Two senior SWEs (feedback incorporated)

---

## Executive Summary

Replace TranscriptInventory's file-system + in-memory metadata with full SQL persistence, matching ConversationMonitor's proven architecture. Fix root cause: discovered transcripts never reach the database, causing metadata loss on restart and circuit breaker failures.

**Core Changes**:
1. Schema: Add `transcript_metadata` table + enhanced `transcripts` columns
2. Identity: Canonical DB-issued IDs with path normalization
3. Persistence: Replace `SidecarMetadataStore` stub with SQL backend
4. Discovery: Single source in `ConversationMonitor` (no duplicate loops)
5. UI: Fix search, use stable `transcript_id` for selection, centralized queue
6. Quality: Proper circuit breaker, freshness checks, backpressure, observability

---

## Shared Utilities (Extract for Reuse)

Both timeline cache and transcript metadata systems share common patterns. Extract these to `ContextifyCore/Database/Utilities/` for reuse:

### ConcurrencyGate.swift
```swift
/// Continuation-based concurrency gate (no spin-wait)
/// Used by: TimelineCacheMissGenerator, TranscriptMetadataOrchestrator
actor ConcurrencyGate {
    private let maxPermits: Int
    private var availablePermits: Int
    private var waiters: [(UUID, CheckedContinuation<Void, Never>)] = []

    init(permits: Int) {
        self.maxPermits = permits
        self.availablePermits = permits
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        let id = UUID()
        await withCheckedContinuation { continuation in
            waiters.append((id, continuation))
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.1.resume()
        } else {
            availablePermits = min(availablePermits + 1, maxPermits)
        }
    }
}
```

### CircuitBreaker.swift
```swift
/// Sliding-window circuit breaker
/// Used by: TimelineCacheMissGenerator, TranscriptMetadataOrchestrator
actor CircuitBreaker {
    private var requestHistory: Deque<RequestOutcome> = []
    private let historyWindowSeconds: TimeInterval
    private let failureThreshold: Double
    private let minimumRequests: Int

    struct RequestOutcome {
        let timestamp: Date
        let success: Bool
    }

    init(windowSeconds: TimeInterval = 300, failureThreshold: Double = 0.6, minimumRequests: Int = 5) {
        self.historyWindowSeconds = windowSeconds
        self.failureThreshold = failureThreshold
        self.minimumRequests = minimumRequests
    }

    func shouldOpen() -> Bool {
        cleanHistory()
        guard requestHistory.count >= minimumRequests else { return false }

        let failures = requestHistory.filter { !$0.success }.count
        let ratio = Double(failures) / Double(requestHistory.count)
        return ratio >= failureThreshold
    }

    func recordSuccess() {
        requestHistory.append(RequestOutcome(timestamp: Date(), success: true))
        cleanHistory()
    }

    func recordFailure() {
        requestHistory.append(RequestOutcome(timestamp: Date(), success: false))
        cleanHistory()
    }

    private func cleanHistory() {
        let cutoff = Date().addingTimeInterval(-historyWindowSeconds)
        while let first = requestHistory.first, first.timestamp < cutoff {
            requestHistory.removeFirst()
        }
    }
}
```

### PathNormalizer.swift
✅ **Already implemented** in Phase 1

### CacheNotifications.swift
```swift
/// Standardized notification names for cache updates
extension NSNotification.Name {
    /// Posted when timeline entry cache is updated (object: CacheKey)
    static let timelineCacheUpdated = NSNotification.Name("TimelineCacheUpdated")

    /// Posted when transcript metadata is updated (object: String transcript_id)
    static let transcriptMetadataUpdated = NSNotification.Name("TranscriptMetadataUpdated")
}
```

**Integration Points:**
- `TimelineCacheMissGenerator`: Replace spin-sleep semaphore with `ConcurrencyGate`
- `TranscriptMetadataOrchestrator`: Use `ConcurrencyGate` + `CircuitBreaker`
- Both: Use standardized notification names

---

## Phase 1: Foundation (Database Schema + Core APIs)

### 1.1 Database Schema Migration

**File**: `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

**Migration Steps**:

```swift
// Add to DatabaseMigrator
migrator.registerMigration("v3_transcript_metadata") { db in
    // Enable foreign keys
    try db.execute(sql: "PRAGMA foreign_keys = ON")

    // Add new columns to transcripts table
    try db.execute(sql: """
        ALTER TABLE transcripts ADD COLUMN normalized_path TEXT;
    """)
    try db.execute(sql: """
        ALTER TABLE transcripts ADD COLUMN path_hash TEXT;
    """)
    try db.execute(sql: """
        ALTER TABLE transcripts ADD COLUMN content_length INTEGER;
    """)
    try db.execute(sql: """
        ALTER TABLE transcripts ADD COLUMN mtime_ns INTEGER;
    """)
    try db.execute(sql: """
        ALTER TABLE transcripts ADD COLUMN content_sha256 TEXT;
    """)

    // Create unique index on provider + path_hash
    try db.execute(sql: """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_path
          ON transcripts(provider, path_hash);
    """)

    // Create transcript_metadata table
    try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS transcript_metadata (
          transcript_id TEXT PRIMARY KEY NOT NULL
            REFERENCES transcripts(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          description TEXT NOT NULL,
          topics_json TEXT NOT NULL,
          confidence REAL NOT NULL,
          strategy TEXT NOT NULL,
          model TEXT NOT NULL,
          message_count INTEGER NOT NULL,
          latency_ms INTEGER NOT NULL,
          needs_review INTEGER NOT NULL DEFAULT 0,
          prompt_version INTEGER NOT NULL,
          generator_version INTEGER NOT NULL,
          transcript_sha256 TEXT NOT NULL,
          generated_at INTEGER NOT NULL
        );
    """)

    // Create indexes for transcript_metadata
    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_generated_at
          ON transcript_metadata(generated_at DESC);
    """)
    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_needs_review
          ON transcript_metadata(needs_review, generated_at DESC);
    """)
    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_sha
          ON transcript_metadata(transcript_sha256);
    """)
    try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_prompt_gen
          ON transcript_metadata(prompt_version, generator_version);
    """)

    // Backfill existing transcripts with normalized_path and path_hash
    let existingTranscripts = try Transcript.fetchAll(db)
    for transcript in existingTranscripts {
        let normalized = PathNormalizer.normalize(transcript.filePath)
        let hash = PathNormalizer.hash(normalized)
        try db.execute(
            sql: "UPDATE transcripts SET normalized_path = ?, path_hash = ? WHERE id = ?",
            arguments: [normalized, hash, transcript.id]
        )
    }
}

// Update userVersion
migrator.registerMigration("v3_user_version") { db in
    try db.execute(sql: "PRAGMA user_version = 3")
}
```

**Path Normalization Utilities**:

```swift
// New file: app/Sources/ContextifyCore/Database/PathNormalizer.swift
import Foundation
import CryptoKit

enum PathNormalizer {
    /// Normalize a file path for canonical comparison
    /// - Resolves symlinks
    /// - Standardizes path (removes .., ., etc.)
    /// - Case-folds on case-insensitive filesystems (macOS default)
    static func normalize(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)

        // Resolve symlinks and standardize
        let resolved = (try? url.resolvingSymlinksInPath()) ?? url
        let standardized = resolved.standardized.path

        // Case-fold on case-insensitive FS (macOS default HFS+/APFS)
        #if os(macOS)
        return standardized.lowercased()
        #else
        return standardized
        #endif
    }

    /// Compute xxHash64 of normalized path (fast, collision-resistant)
    static func hash(_ normalizedPath: String) -> String {
        // Use SHA256 for now (xxHash requires additional dependency)
        let data = Data(normalizedPath.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

### 1.2 Repository Layer

**File**: `app/Sources/ContextifyCore/Database/Repositories.swift`

**Add `TranscriptMetadataRepository`**:

```swift
/// Repository for transcript-level metadata (title, description, topics)
struct TranscriptMetadataRepository {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    /// Save metadata for a transcript
    func save(transcriptId: String, metadata: TranscriptMetadata) throws {
        try db.write { db in
            let topicsJSON = try JSONEncoder().encode(metadata.topics)

            try db.execute(
                sql: """
                    INSERT INTO transcript_metadata (
                        transcript_id, title, description, topics_json, confidence,
                        strategy, model, message_count, latency_ms, needs_review,
                        prompt_version, generator_version, transcript_sha256, generated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(transcript_id) DO UPDATE SET
                        title = excluded.title,
                        description = excluded.description,
                        topics_json = excluded.topics_json,
                        confidence = excluded.confidence,
                        strategy = excluded.strategy,
                        model = excluded.model,
                        message_count = excluded.message_count,
                        latency_ms = excluded.latency_ms,
                        needs_review = excluded.needs_review,
                        prompt_version = excluded.prompt_version,
                        generator_version = excluded.generator_version,
                        transcript_sha256 = excluded.transcript_sha256,
                        generated_at = excluded.generated_at
                """,
                arguments: [
                    transcriptId, metadata.title, metadata.description,
                    String(data: topicsJSON, encoding: .utf8) ?? "[]",
                    metadata.confidence, metadata.strategy, metadata.model,
                    metadata.messageCount, metadata.latencyMs, metadata.needsReview ? 1 : 0,
                    metadata.promptVersion, metadata.generatorVersion,
                    metadata.transcriptSHA256, Int(metadata.generatedAt.timeIntervalSince1970)
                ]
            )
        }
    }

    /// Get metadata for a single transcript
    func get(transcriptId: String) throws -> TranscriptMetadata? {
        try db.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM transcript_metadata WHERE transcript_id = ?",
                arguments: [transcriptId]
            ) else {
                return nil
            }

            return try parseMetadata(from: row)
        }
    }

    /// Get metadata for multiple transcripts (batch query)
    func getBatch(transcriptIds: [String]) throws -> [String: TranscriptMetadata] {
        guard !transcriptIds.isEmpty else { return [:] }

        return try db.read { db in
            let placeholders = transcriptIds.map { _ in "?" }.joined(separator: ",")
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM transcript_metadata WHERE transcript_id IN (\(placeholders))",
                arguments: StatementArguments(transcriptIds)
            )

            var result: [String: TranscriptMetadata] = [:]
            for row in rows {
                let transcriptId: String = row["transcript_id"]
                if let metadata = try? parseMetadata(from: row) {
                    result[transcriptId] = metadata
                }
            }
            return result
        }
    }

    /// Delete metadata for a transcript
    func delete(transcriptId: String) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM transcript_metadata WHERE transcript_id = ?",
                arguments: [transcriptId]
            )
        }
    }

    /// Delete all metadata matching a predicate (e.g., heuristic-generated)
    func deleteWhere(predicate: String, arguments: StatementArguments) throws {
        try db.write { db in
            try db.execute(
                sql: "DELETE FROM transcript_metadata WHERE \(predicate)",
                arguments: arguments
            )
        }
    }

    // MARK: - Private Helpers

    private func parseMetadata(from row: Row) throws -> TranscriptMetadata {
        let topicsJSON: String = row["topics_json"]
        let topics = (try? JSONDecoder().decode([String].self, from: Data(topicsJSON.utf8))) ?? []

        return TranscriptMetadata(
            title: row["title"],
            description: row["description"],
            topics: topics,
            confidence: row["confidence"],
            strategy: row["strategy"],
            model: row["model"],
            messageCount: row["message_count"],
            latencyMs: row["latency_ms"],
            needsReview: (row["needs_review"] as Int) == 1,
            promptVersion: row["prompt_version"],
            generatorVersion: row["generator_version"],
            transcriptSHA256: row["transcript_sha256"],
            generatedAt: Date(timeIntervalSince1970: TimeInterval(row["generated_at"] as Int))
        )
    }
}
```

### 1.3 TranscriptOrchestrator APIs

**File**: `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`

**Add new methods**:

```swift
// MARK: - Discovery & Identity

/// Discovered transcript from file system scan
struct DiscoveredTranscript: Sendable {
    let fileURL: URL
    let provider: String  // "claude.code", "codex.cli"
    let providerSessionId: String
}

/// Resolved transcript with canonical ID
struct ResolvedTranscript: Sendable {
    let transcriptId: String
    let fileURL: URL
}

/// Upsert discovered transcripts in a single transaction
/// Returns canonical transcript IDs for UI consumption
func upsertTranscripts(
    projectId: String,
    discovered: [DiscoveredTranscript]
) throws -> [ResolvedTranscript] {
    try dbManager.queue.write { db in
        var resolved: [ResolvedTranscript] = []

        for item in discovered {
            // Normalize path
            let normalized = PathNormalizer.normalize(item.fileURL.path)
            let pathHash = PathNormalizer.hash(normalized)

            // Get file metadata
            let attrs = try? FileManager.default.attributesOfItem(atPath: item.fileURL.path)
            let contentLength = (attrs?[.size] as? Int64) ?? 0
            let modDate = (attrs?[.modificationDate] as? Date) ?? Date()
            let mtimeNs = Int(modDate.timeIntervalSince1970 * 1_000_000_000)

            // Compute SHA256 if small enough (< 10MB), otherwise use placeholder
            let contentSHA256: String
            if contentLength < 10_000_000 {
                let data = try? Data(contentsOf: item.fileURL)
                if let data = data {
                    let hash = SHA256.hash(data: data)
                    contentSHA256 = hash.compactMap { String(format: "%02x", $0) }.joined()
                } else {
                    contentSHA256 = "pending"
                }
            } else {
                contentSHA256 = "large-file"
            }

            // Upsert transcript
            try db.execute(sql: """
                INSERT INTO transcripts (
                    id, project_id, file_path, provider, provider_session_id,
                    normalized_path, path_hash, content_length, mtime_ns, content_sha256,
                    created_at, updated_at
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                )
                ON CONFLICT(provider, path_hash) DO UPDATE SET
                    file_path = excluded.file_path,
                    provider_session_id = excluded.provider_session_id,
                    content_length = excluded.content_length,
                    mtime_ns = excluded.mtime_ns,
                    content_sha256 = excluded.content_sha256,
                    updated_at = excluded.updated_at
                RETURNING id
            """, arguments: [
                UUID().uuidString,  // Will be replaced by RETURNING if conflict
                projectId,
                item.fileURL.path,
                item.provider,
                item.providerSessionId,
                normalized,
                pathHash,
                contentLength,
                mtimeNs,
                contentSHA256,
                Int(Date().timeIntervalSince1970),
                Int(Date().timeIntervalSince1970)
            ])

            // Get the ID (either inserted or existing)
            if let transcriptId = try String.fetchOne(db, sql: """
                SELECT id FROM transcripts
                WHERE provider = ? AND path_hash = ?
            """, arguments: [item.provider, pathHash]) {
                resolved.append(ResolvedTranscript(
                    transcriptId: transcriptId,
                    fileURL: item.fileURL
                ))
            }
        }

        return resolved
    }
}

/// Resolve canonical transcript ID for a file URL + provider
/// Idempotent - safe to call multiple times
func resolveTranscriptId(fileURL: URL, provider: String) throws -> String? {
    let normalized = PathNormalizer.normalize(fileURL.path)
    let pathHash = PathNormalizer.hash(normalized)

    return try dbManager.queue.read { db in
        try String.fetchOne(db, sql: """
            SELECT id FROM transcripts
            WHERE provider = ? AND path_hash = ?
        """, arguments: [provider, pathHash])
    }
}

// MARK: - Metadata Persistence

private lazy var metadataRepository = TranscriptMetadataRepository(db: dbManager.queue)

/// Save metadata for a transcript
func saveTranscriptMetadata(
    transcriptId: String,
    metadata: TranscriptMetadata
) throws {
    try metadataRepository.save(transcriptId: transcriptId, metadata: metadata)
}

/// Get metadata for a single transcript
func getTranscriptMetadata(transcriptId: String) throws -> TranscriptMetadata? {
    try metadataRepository.get(transcriptId: transcriptId)
}

/// Get metadata for multiple transcripts (batch query)
func getTranscriptMetadataBatch(transcriptIds: [String]) throws -> [String: TranscriptMetadata] {
    try metadataRepository.getBatch(transcriptIds: transcriptIds)
}

/// Invalidate metadata for a transcript (forces regeneration)
func invalidateTranscriptMetadata(transcriptId: String) throws {
    try metadataRepository.delete(transcriptId: transcriptId)
}

/// Delete all heuristic metadata (for "Flush Heuristic Cache" action)
func deleteHeuristicMetadata() throws {
    try metadataRepository.deleteWhere(
        predicate: "model = ? OR strategy LIKE ?",
        arguments: ["heuristic", "%heuristic%"]
    )
}
```

---

## Phase 2: Discovery & Persistence Integration

### 2.1 ConversationMonitor: Single Source of Discovery

**File**: `Contextify/Contextify/ConversationMonitor.swift`

**Modify `discoverNewTranscripts` to use new upsert API**:

```swift
nonisolated private func discoverNewTranscripts(
    projectId: String,
    orchestrator: TranscriptOrchestrator
) async throws {
    // ... existing file system scan code ...

    // Build discovered transcripts list
    var discovered: [DiscoveredTranscript] = []

    // Claude Code transcripts
    if let claudeDir = getClaudeProjectDir(projectRoot: projectRoot) {
        let files = try FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }

        for fileURL in files {
            discovered.append(DiscoveredTranscript(
                fileURL: fileURL,
                provider: "claude.code",
                providerSessionId: fileURL.lastPathComponent
            ))
        }
    }

    // Codex CLI transcripts (similar pattern)
    // ... add Codex discovery ...

    // Upsert all discovered transcripts in one transaction
    let resolved = try orchestrator.upsertTranscripts(
        projectId: projectId,
        discovered: discovered
    )

    // Start file watchers for newly discovered transcripts
    for item in resolved {
        try orchestrator.startWatching(
            transcriptId: item.transcriptId,
            fileURL: item.fileURL
        )
    }

    // Update allSessions on main actor
    let transcripts = try orchestrator.getTranscripts(forProject: projectId)
    let latestTimestamps = try orchestrator.latestTimestampsByTranscript(projectId: projectId)
    let sessions = Self.mapTranscriptsToSessions(
        transcripts: transcripts,
        latestTimestamps: latestTimestamps
    )

    await MainActor.run {
        self.allSessions = sessions
        self.log.info("✅ Discovered and persisted \(resolved.count) transcripts")
    }
}
```

### 2.2 Remove Duplicate Discovery from TranscriptInventory

**File**: `Contextify/Contextify/TranscriptInventoryView.swift`

**Remove file-system scanning**:

```swift
// OLD (DELETE):
.onChange(of: monitor.allSessions) { _, newSessions in
    Task {
        await loadMetadataForSessions(newSessions)  // ❌ Remove this
    }
}

// NEW (KEEP):
.task {
    // Inventory window just displays what's already in DB
    // ConversationMonitor handles discovery
    await loadMetadataForSessions(monitor.allSessions)
}
```

---

## Phase 3: Metadata Orchestrator SQL Integration

### 3.1 Replace SidecarMetadataStore

**File**: `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Replace in-memory store with SQL backend**:

```swift
actor TranscriptMetadataOrchestrator {
    static let shared = TranscriptMetadataOrchestrator()

    private let log = Logger(subsystem: "dev.contextify.metadata", category: "Orchestrator")
    private let orchestrator: TranscriptOrchestrator  // ← SQL backend
    private let parser = TranscriptParser()
    private let builder = ContextBuilder()
    private let llm: TranscriptMetadataLLM
    private let postProcessor = MetadataPostProcessor()

    // Centralized queue (keyed by transcript_id)
    private var pendingQueue: [String: MetadataGenerationTask] = [:]
    private var activeTasks: [String: Task<TranscriptMetadata, Error>] = [:]

    // Backpressure: continuation-based gate
    private var llmGate: ContinuationGate

    // Circuit breaker: sliding window deque
    private var requestHistory: Deque<RequestOutcome> = []
    private let historyWindowSeconds: TimeInterval = 300  // 5 minutes

    struct RequestOutcome {
        let timestamp: Date
        let success: Bool
    }

    private init() {
        self.orchestrator = try! TranscriptOrchestrator(dbManager: .shared)
        self.llm = TranscriptMetadataLLM.shared
        self.llmGate = ContinuationGate(permits: 2)  // Max 2 concurrent LLM calls
    }

    // MARK: - Public API

    /// Ensure metadata exists for a transcript ID
    /// Idempotent - safe to call multiple times
    func ensureMetadata(
        for transcriptId: String,
        fileURL: URL,
        forceRegenerate: Bool = false
    ) async throws -> TranscriptMetadata {
        // Check SQL cache first
        if !forceRegenerate,
           let cached = try orchestrator.getTranscriptMetadata(transcriptId: transcriptId),
           await isFresh(cached, fileURL: fileURL) {
            log.info("✅ Using cached metadata for transcript \(transcriptId)")
            return cached
        }

        // Check if already generating
        if let existing = activeTasks[transcriptId] {
            log.info("⏳ Reusing existing generation task for \(transcriptId)")
            return try await existing.value
        }

        // Start new generation task
        let task = Task<TranscriptMetadata, Error> {
            defer { Task { await self.removeTask(for: transcriptId) } }
            return try await self.generateMetadata(
                transcriptId: transcriptId,
                fileURL: fileURL,
                forceRegenerate: forceRegenerate
            )
        }

        activeTasks[transcriptId] = task
        return try await task.value
    }

    // MARK: - Private Implementation

    private func generateMetadata(
        transcriptId: String,
        fileURL: URL,
        forceRegenerate: Bool
    ) async throws -> TranscriptMetadata {
        let startTime = Date()

        // Parse transcript
        let exchanges = try parser.parseExchanges(url: fileURL)

        // Handle very short transcripts
        if exchanges.count < 3 {
            log.info("Very short transcript (\(exchanges.count) exchanges), using heuristic")
            let metadata = HeuristicMetadata.generate(exchanges: exchanges)
            try orchestrator.saveTranscriptMetadata(
                transcriptId: transcriptId,
                metadata: metadata
            )
            return metadata
        }

        // Check circuit breaker
        if shouldUseCircuitBreaker() {
            log.warning("⚠️ Circuit breaker active, using heuristic fallback")
            let metadata = HeuristicMetadata.generate(exchanges: exchanges)
            try orchestrator.saveTranscriptMetadata(
                transcriptId: transcriptId,
                metadata: metadata
            )
            recordOutcome(success: false)
            return metadata
        }

        // Build context
        let strategy = selectStrategy(exchangeCount: exchanges.count)
        let availableTokens = await calculateTokenBudget(strategy: strategy, exchangeCount: exchanges.count)
        let context = try builder.build(
            exchanges: exchanges,
            strategy: strategy,
            budgetTokens: availableTokens
        )

        // Acquire LLM gate (continuation-based, no spin)
        await llmGate.acquire()
        defer { Task { await llmGate.release() } }

        // Call LLM with retry + fallback
        var metadata: TranscriptMetadata
        do {
            metadata = try await callLLM(context: context, exchanges: exchanges, strategy: strategy)
            recordOutcome(success: true)
        } catch {
            log.error("LLM call failed: \(error.localizedDescription)")
            recordOutcome(success: false)

            // Fallback to heuristic
            metadata = HeuristicMetadata.generate(exchanges: exchanges)
            metadata.strategy = "heuristic-after-failure"
        }

        // Finalize metadata
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let data = try? Data(contentsOf: fileURL), data.count < 10_000_000 {
            let hash = SHA256.hash(data: data)
            metadata.transcriptSHA256 = hash.compactMap { String(format: "%02x", $0) }.joined()
        }
        metadata.latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Save to SQL
        try orchestrator.saveTranscriptMetadata(
            transcriptId: transcriptId,
            metadata: metadata
        )

        // Post notification for UI update
        await MainActor.run {
            NotificationCenter.default.post(
                name: .transcriptMetadataUpdated,
                object: transcriptId
            )
        }

        return metadata
    }

    private func isFresh(_ metadata: TranscriptMetadata, fileURL: URL) async -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modDate = attrs[.modificationDate] as? Date,
              let fileSize = attrs[.size] as? Int64 else {
            return false
        }

        // Fast path: check mtime + size
        let mtimeNs = Int(modDate.timeIntervalSince1970 * 1_000_000_000)
        let transcript = try? orchestrator.getTranscripts(forProject: "").first { $0.filePath == fileURL.path }

        if let t = transcript,
           t.mtimeNs == mtimeNs,
           t.contentLength == fileSize {
            return true
        }

        // Slow path: recompute SHA256 if mtime changed
        if fileSize < 10_000_000,
           let data = try? Data(contentsOf: fileURL) {
            let hash = SHA256.hash(data: data)
            let newSHA = hash.compactMap { String(format: "%02x", $0) }.joined()
            return newSHA == metadata.transcriptSHA256
        }

        return false
    }

    // MARK: - Circuit Breaker (Sliding Window)

    private func shouldUseCircuitBreaker() -> Bool {
        cleanHistory()

        guard requestHistory.count >= 5 else { return false }

        let failures = requestHistory.filter { !$0.success }.count
        let ratio = Double(failures) / Double(requestHistory.count)

        return ratio >= 0.6  // Open if 60%+ failures
    }

    private func recordOutcome(success: Bool) {
        requestHistory.append(RequestOutcome(timestamp: Date(), success: success))
        cleanHistory()
    }

    private func cleanHistory() {
        let cutoff = Date().addingTimeInterval(-historyWindowSeconds)
        while let first = requestHistory.first, first.timestamp < cutoff {
            requestHistory.removeFirst()
        }
    }

    private func removeTask(for transcriptId: String) {
        activeTasks.removeValue(forKey: transcriptId)
    }
}

// MARK: - Continuation-Based Gate

actor ContinuationGate {
    private let maxPermits: Int
    private var availablePermits: Int
    private var waiters: [(UUID, CheckedContinuation<Void, Never>)] = []

    init(permits: Int) {
        self.maxPermits = permits
        self.availablePermits = permits
    }

    func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        let id = UUID()
        await withCheckedContinuation { continuation in
            waiters.append((id, continuation))
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.1.resume()
        } else {
            availablePermits = min(availablePermits + 1, maxPermits)
        }
    }
}

// MARK: - Notification Extension

extension NSNotification.Name {
    static let transcriptMetadataUpdated = NSNotification.Name("TranscriptMetadataUpdated")
}
```

---

## Phase 4: UI Integration

### 4.1 Fix TranscriptInventoryView

**File**: `Contextify/Contextify/TranscriptInventoryView.swift`

**Key Changes**:
1. Use `transcript_id` for selection (not URL)
2. Fix search to actually filter
3. Centralize metadata loading (no per-row Tasks)
4. Observe notifications for updates

```swift
struct TranscriptInventoryView: View {
    @Environment(ConversationMonitor.self) private var monitor
    let onSelectSession: (TranscriptSession) -> Void

    @State private var selectedTranscriptId: String?  // ← Changed from URL
    @State private var searchText = ""
    @State private var groupingMode: GroupingMode = .provider
    @State private var metadata: [String: TranscriptMetadata] = [:]  // ← Keyed by transcript_id
    @State private var loadingMetadata: Set<String> = []

    var body: some View {
        Group {
            if let error = monitor.lastError, monitor.allSessions.isEmpty {
                errorView(error)
            } else {
                HSplitView {
                    sessionListView
                        .frame(minWidth: 250)
                    detailView
                        .frame(minWidth: 500)
                }
            }
        }
    }

    private var selectedSession: TranscriptSession? {
        guard let id = selectedTranscriptId else { return nil }
        return monitor.allSessions.first { session in
            // Resolve transcript_id from session
            guard let transcriptId = try? resolveTranscriptId(for: session) else { return false }
            return transcriptId == id
        }
    }

    @ViewBuilder
    private var sessionListView: some View {
        VStack(spacing: 0) {
            // ... header ...

            // Session list with transcript_id-based selection
            List(filteredSessions, id: \.self, selection: $selectedTranscriptId) { session in
                sessionRow(session)
                    .tag(try? resolveTranscriptId(for: session))
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search transcripts")
            .task {
                await loadMetadataForAllSessions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .transcriptMetadataUpdated)) { notification in
                guard let transcriptId = notification.object as? String else { return }
                Task { await refreshMetadata(for: transcriptId) }
            }
        }
    }

    // MARK: - Filtered Sessions (Fix Search)

    private var filteredSessions: [TranscriptSession] {
        let sessions = monitor.allSessions
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter { session in
            // Search in identifier, file path, and metadata title/description
            session.identifier.localizedCaseInsensitiveContains(searchText) ||
            session.fileURL.path.localizedCaseInsensitiveContains(searchText) ||
            {
                guard let transcriptId = try? resolveTranscriptId(for: session),
                      let meta = metadata[transcriptId] else {
                    return false
                }
                return meta.title.localizedCaseInsensitiveContains(searchText) ||
                       meta.description.localizedCaseInsensitiveContains(searchText)
            }()
        }
    }

    // MARK: - Metadata Loading (Centralized)

    @MainActor
    private func loadMetadataForAllSessions() async {
        // Resolve transcript IDs
        var transcriptIds: [String] = []
        for session in monitor.allSessions {
            if let id = try? resolveTranscriptId(for: session) {
                transcriptIds.append(id)
            }
        }

        // Batch query SQL
        guard let orchestrator = monitor.orchestrator else { return }
        let cachedMetadata = try? orchestrator.getTranscriptMetadataBatch(transcriptIds: transcriptIds)

        // Populate metadata dictionary
        for session in monitor.allSessions {
            guard let transcriptId = try? resolveTranscriptId(for: session) else { continue }

            if let cached = cachedMetadata?[transcriptId] {
                metadata[transcriptId] = cached
            } else {
                // Cache miss - enqueue for generation (don't spawn Task here!)
                loadingMetadata.insert(transcriptId)
                Task {
                    await queueMetadataGeneration(transcriptId: transcriptId, fileURL: session.fileURL)
                }
            }
        }
    }

    @MainActor
    private func queueMetadataGeneration(transcriptId: String, fileURL: URL) async {
        defer { loadingMetadata.remove(transcriptId) }

        do {
            let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
                for: transcriptId,
                fileURL: fileURL
            )
            metadata[transcriptId] = generated
        } catch {
            // Failed - show placeholder
        }
    }

    @MainActor
    private func refreshMetadata(for transcriptId: String) async {
        guard let orchestrator = monitor.orchestrator else { return }
        if let refreshed = try? orchestrator.getTranscriptMetadata(transcriptId: transcriptId) {
            metadata[transcriptId] = refreshed
        }
    }

    // MARK: - Helpers

    private func resolveTranscriptId(for session: TranscriptSession) throws -> String? {
        let provider: String
        switch session.provider {
        case .claudeCode: provider = "claude.code"
        case .codexCLI: provider = "codex.cli"
        case .other: provider = "other"
        }

        return try monitor.orchestrator?.resolveTranscriptId(
            fileURL: session.fileURL,
            provider: provider
        )
    }

    // MARK: - Flush Heuristic Cache (True Flush)

    private func flushHeuristicCache() {
        Task { @MainActor in
            guard let orchestrator = monitor.orchestrator else { return }

            // Delete all heuristic metadata from SQL
            try? orchestrator.deleteHeuristicMetadata()

            // Clear in-memory cache
            for (transcriptId, meta) in metadata {
                if meta.model == "heuristic" || meta.strategy.contains("heuristic") {
                    metadata.removeValue(forKey: transcriptId)
                    loadingMetadata.insert(transcriptId)

                    // Enqueue for regeneration
                    if let session = monitor.allSessions.first(where: {
                        (try? resolveTranscriptId(for: $0)) == transcriptId
                    }) {
                        Task {
                            await queueMetadataGeneration(
                                transcriptId: transcriptId,
                                fileURL: session.fileURL
                            )
                        }
                    }
                }
            }

            showingFlushAlert = true
        }
    }
}
```

### 4.2 Add Inventory Icon to ContentView

**File**: `Contextify/Contextify/ContentView.swift`

**Add icon button next to session dropdown**:

```swift
// In header section, add before session dropdown:
Button {
    openInventoryWindow()
} label: {
    Image(systemName: "tray.full.fill")
        .help("Browse All Transcripts")
}
.buttonStyle(.borderless)

// Add window opener method:
private func openInventoryWindow() {
    // Check if window already exists
    if let window = NSApp.windows.first(where: { $0.title == "Transcripts" }) {
        window.makeKeyAndOrderFront(nil)
        return
    }

    // Create new window
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
        styleMask: [.titled, .closable, .resizable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Transcripts"
    window.contentView = NSHostingView(
        rootView: TranscriptInventoryWindow()
            .environment(monitor)
    )
    window.center()
    window.makeKeyAndOrderFront(nil)
}
```

---

## Phase 5: Testing & Validation

### 5.1 Unit Tests

**File**: `Contextify/ContextifyTests/TranscriptPersistenceTests.swift`

```swift
import XCTest
@testable import ContextifyCore

class TranscriptPersistenceTests: XCTestCase {
    var tempDB: DatabaseQueue!
    var orchestrator: TranscriptOrchestrator!

    override func setUp() async throws {
        // Create temp database
        tempDB = try DatabaseQueue()

        // Run migrations
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v3_transcript_metadata") { db in
            // ... full migration code ...
        }
        try migrator.migrate(tempDB)

        orchestrator = try TranscriptOrchestrator(dbManager: DatabaseManager(queue: tempDB))
    }

    func testUpsertTranscriptsCreatesNewRecords() throws {
        let projectId = try orchestrator.getOrCreateProject(name: "test", rootPath: "/tmp/test")

        let discovered = [
            DiscoveredTranscript(
                fileURL: URL(fileURLWithPath: "/tmp/test/session1.jsonl"),
                provider: "claude.code",
                providerSessionId: "session1.jsonl"
            )
        ]

        let resolved = try orchestrator.upsertTranscripts(
            projectId: projectId,
            discovered: discovered
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertNotNil(resolved.first?.transcriptId)
    }

    func testUpsertTranscriptsIsIdempotent() throws {
        let projectId = try orchestrator.getOrCreateProject(name: "test", rootPath: "/tmp/test")

        let discovered = [
            DiscoveredTranscript(
                fileURL: URL(fileURLWithPath: "/tmp/test/session1.jsonl"),
                provider: "claude.code",
                providerSessionId: "session1.jsonl"
            )
        ]

        let first = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
        let second = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)

        XCTAssertEqual(first.first?.transcriptId, second.first?.transcriptId)
    }

    func testPathNormalizationHandlesSymlinks() throws {
        // Create temp file and symlink
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.jsonl")
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())

        let symlinkPath = NSTemporaryDirectory() + "link.jsonl"
        try? FileManager.default.removeItem(atPath: symlinkPath)
        try FileManager.default.createSymbolicLink(
            atPath: symlinkPath,
            withDestinationPath: tempFile.path
        )

        let normalized1 = PathNormalizer.normalize(tempFile.path)
        let normalized2 = PathNormalizer.normalize(symlinkPath)

        XCTAssertEqual(normalized1, normalized2)

        // Cleanup
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(atPath: symlinkPath)
    }

    func testMetadataPersistence() throws {
        let projectId = try orchestrator.getOrCreateProject(name: "test", rootPath: "/tmp/test")

        let discovered = [
            DiscoveredTranscript(
                fileURL: URL(fileURLWithPath: "/tmp/test/session1.jsonl"),
                provider: "claude.code",
                providerSessionId: "session1.jsonl"
            )
        ]

        let resolved = try orchestrator.upsertTranscripts(projectId: projectId, discovered: discovered)
        let transcriptId = resolved.first!.transcriptId

        // Save metadata
        let metadata = TranscriptMetadata(
            title: "Test Session",
            description: "Testing persistence",
            topics: ["testing", "swift"],
            confidence: 0.95,
            strategy: "full",
            model: "foundation",
            messageCount: 10,
            latencyMs: 500,
            needsReview: false,
            promptVersion: 2,
            generatorVersion: 1,
            transcriptSHA256: "abc123",
            generatedAt: Date()
        )

        try orchestrator.saveTranscriptMetadata(transcriptId: transcriptId, metadata: metadata)

        // Retrieve metadata
        let retrieved = try orchestrator.getTranscriptMetadata(transcriptId: transcriptId)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.title, "Test Session")
        XCTAssertEqual(retrieved?.topics.count, 2)
    }

    func testForeignKeyConstraintEnforced() throws {
        let nonExistentId = UUID().uuidString

        let metadata = TranscriptMetadata(
            title: "Orphaned",
            description: "Should fail",
            topics: [],
            confidence: 0.5,
            strategy: "test",
            model: "test",
            messageCount: 0,
            latencyMs: 0,
            needsReview: false,
            promptVersion: 1,
            generatorVersion: 1,
            transcriptSHA256: "",
            generatedAt: Date()
        )

        XCTAssertThrowsError(
            try orchestrator.saveTranscriptMetadata(
                transcriptId: nonExistentId,
                metadata: metadata
            )
        )
    }
}
```

### 5.2 Integration Tests

**File**: `Contextify/ContextifyTests/TranscriptInventoryIntegrationTests.swift`

```swift
import XCTest
@testable import Contextify

@MainActor
class TranscriptInventoryIntegrationTests: XCTestCase {
    var monitor: ConversationMonitor!

    override func setUp() async throws {
        monitor = ConversationMonitor.shared

        // Clean database
        try? FileManager.default.removeItem(
            at: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Contextify/transcripts.db")
        )

        await monitor.startMonitoring()
    }

    func testColdStartLoadsFromDatabase() async throws {
        // Create test transcript
        let testFile = createTestTranscript()

        // First run: discover and persist
        try await monitor.discoverNewTranscripts(
            projectId: monitor.currentProjectId!,
            orchestrator: monitor.orchestrator!
        )

        XCTAssertGreaterThan(monitor.allSessions.count, 0)

        // Stop monitoring (simulating app restart)
        await monitor.stopMonitoring()

        // Restart monitoring
        await monitor.startMonitoring()
        await monitor.loadAllSessionsFromDatabase()

        // Should load from DB without re-scanning file system
        XCTAssertGreaterThan(monitor.allSessions.count, 0)

        // Cleanup
        try? FileManager.default.removeItem(at: testFile)
    }

    private func createTestTranscript() -> URL {
        let projectDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects/-tmp-test")
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let file = projectDir.appendingPathComponent("test-\(UUID().uuidString).jsonl")
        let content = """
        {"type":"user","timestamp":"2025-10-18T12:00:00Z","content":[{"type":"text","text":"Hello"}]}
        {"type":"assistant","timestamp":"2025-10-18T12:00:01Z","content":[{"type":"text","text":"Hi"}]}
        """
        try? content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
```

### 5.3 Manual Testing Checklist

1. **Clean State**:
   ```bash
   make clean-db
   make build
   # Launch app
   ```

2. **Verify Persistence**:
   - Open Transcripts
   - Check logs: "Loaded N sessions from database"
   - Restart app
   - Check logs: No LLM generation, metadata loaded from SQL
   - Verify metadata displays correctly

3. **Verify Circuit Breaker Fixed**:
   - Monitor logs during inventory loading
   - Should see: "Using cached metadata" (not "Circuit breaker active")

4. **Verify Search**:
   - Type in search box
   - List should filter in real-time
   - Clear search → all sessions return

5. **Verify Identity Stability**:
   - Rename a transcript file
   - Verify it's still recognized (path normalization)

6. **Verify Metadata Invalidation**:
   - Modify a transcript file
   - Check logs: Metadata invalidated, regenerated
   - Verify new metadata saved to SQL

---

## Phase 6: Observability & Metrics

### 6.1 Add Metrics Tracking

**File**: `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Add metrics collection**:

```swift
// Add to TranscriptMetadataOrchestrator
private var metrics = MetricsCollector()

struct MetricsCollector {
    var cacheHits: Int = 0
    var cacheMisses: Int = 0
    var llmCallsStarted: Int = 0
    var llmCallsCompleted: Int = 0
    var llmCallsFailed: Int = 0
    var circuitBreakerOpens: Int = 0

    var hitRate: Double {
        let total = cacheHits + cacheMisses
        guard total > 0 else { return 0 }
        return Double(cacheHits) / Double(total)
    }
}

// Log metrics periodically
private func logMetricsSummary() {
    log.info("""
        📊 Metadata Metrics:
        - Cache hit rate: \(String(format: "%.1f%%", metrics.hitRate * 100))
        - LLM calls: \(metrics.llmCallsCompleted) completed, \(metrics.llmCallsFailed) failed
        - Circuit breaker opens: \(metrics.circuitBreakerOpens)
    """)
}

// Call logMetricsSummary every 100 requests
private var requestCounter = 0
private func maybeLogMetrics() {
    requestCounter += 1
    if requestCounter % 100 == 0 {
        logMetricsSummary()
    }
}
```

---

## Rollout Plan

### Step 1: Schema Migration (Low Risk)
- Deploy schema changes
- Verify migration succeeds on existing DBs
- Test FK constraints and indexes
- **Checkpoint**: Schema ready, no functional changes yet

### Step 2: API Layer (Medium Risk)
- Add new TranscriptOrchestrator methods
- Test with unit tests
- **Checkpoint**: APIs available but not called by UI

### Step 3: Discovery Integration (Medium Risk)
- Update ConversationMonitor discovery loop
- Test discovery → persistence flow
- **Checkpoint**: Transcripts persist to DB on discovery

### Step 4: Metadata Persistence (High Risk)
- Replace SidecarMetadataStore with SQL
- Update TranscriptMetadataOrchestrator
- **Checkpoint**: Metadata persists across restarts

### Step 5: UI Integration (High Risk)
- Update TranscriptInventoryView
- Fix search, selection, metadata loading
- **Checkpoint**: Full end-to-end working

### Step 6: Polish (Low Risk)
- Add observability metrics
- Tune circuit breaker
- Performance optimization
- **Checkpoint**: Production-ready

---

## Success Criteria

✅ **Functional**:
- Transcripts discovered from file system persist to database
- Metadata generates once per transcript, persists across restarts
- No circuit breaker errors in logs after first generation
- Search filters inventory list in real-time
- Selection stable across file renames

✅ **Performance**:
- Cold start: <500ms to load 100 sessions from DB
- Metadata generation: <2s per transcript
- UI remains responsive during background generation
- No main thread blocking

✅ **Quality**:
- Zero duplicate transcripts (path normalization works)
- Zero orphaned metadata (FK constraints enforced)
- Circuit breaker opens/closes correctly
- Metrics logged every 100 requests

---

## Risk Mitigation

**Database Migration Failure**:
- Mitigation: Test migration on copy of production DB before deploy
- Rollback: Revert schema version, app falls back to file-system mode

**Performance Regression**:
- Mitigation: Benchmark before/after with 1000+ transcripts
- Rollback: Feature flag to disable SQL persistence

**Data Loss**:
- Mitigation: Export/import tools for metadata
- Backup: Daily snapshot of transcripts.db

---

**End of Implementation Plan**
