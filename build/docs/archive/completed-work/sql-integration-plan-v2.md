# SQL Backend Hard Cutover Plan v2

**Status:** Implementation Plan (Hard Cutover - No Fallback)
**Created:** 2025-10-11
**Supersedes:** sql-integration-plan-v1.md

## Executive Summary

We are **deleting the legacy filesystem path** and wiring the UI straight to SQLite. No toggles, no fallback. This branch removes file-based code and makes the SQL backend the single source of truth.

**Key Decisions:**
- Single data path: UI → `TranscriptOrchestrator` → Repos → SQLite
- No `@MainActor` on data layer (GRDB's `DatabasePool` handles concurrency)
- Realtime via `TranscriptUpdated` notifications on main queue
- Streaming hoover runs off-main, returns `transcript_sha256` for metadata invalidation
- Cache & metadata persist exclusively to SQL tables

---

## Part 1: Schema Migrations (DatabaseMigrator)

Switch to GRDB's `DatabaseMigrator` for clean schema evolution.

### Migration v1 (Current - Already Merged)

Base tables with optimizations:
- `timeline_cache` WITHOUT ROWID ✅
- `idx_entries_completion` with timestamp DESC ✅
- All foreign keys and indexes

### Migration v2 (Precompute Window for Fast Cache Joins)

**Problem:** Computing window hashes per-row requires extra SELECTs for context.

**Solution:** Store window components directly on entries for single-query feed+cache joins.

```swift
// In DatabaseSchema.swift
static func createMigrator() -> DatabaseMigrator {
  var migrator = DatabaseMigrator()

  // v1: Base schema (existing)
  migrator.registerMigration("v1_base") { db in
    try migrate(db) // Existing schema creation
  }

  // v2: Window fields for cache join optimization
  migrator.registerMigration("v2_window_sha") { db in
    try db.alter(table: "transcript_entries") { t in
      t.add(column: "prev1_id", .text)
      t.add(column: "prev2_id", .text)
      t.add(column: "window_sha256", .text)
    }

    // Covering index for feed+cache join (single round trip)
    try db.create(
      index: "idx_entries_feed_cover",
      on: "transcript_entries",
      columns: ["project_id", "timestamp", "content_sha256", "window_sha256"],
      condition: "display_in_timeline = 1",
      ifNotExists: true
    )
  }

  return migrator
}
```

**Update DatabaseManager.swift:**

```swift
private func openDatabase() throws -> DatabasePool {
  // ... existing config ...

  let pool = try DatabasePool(path: dbPath.path, configuration: config)

  // Run migrations instead of direct schema creation
  let migrator = DatabaseSchema.createMigrator()
  try migrator.migrate(pool)

  // Validate database
  try validateDatabase(pool)

  log.info("Database opened and migrated successfully")
  return pool
}
```

### Migration v3 (Optional - FTS5 for Search)

Keep LIKE for initial cutover, but FTS5 is fast and trivial:

```swift
migrator.registerMigration("v3_fts5") { db in
  try db.execute(sql: """
    CREATE VIRTUAL TABLE IF NOT EXISTS transcript_entries_fts
    USING fts5(content, entry_id UNINDEXED, project_id UNINDEXED, tokenize='unicode61')
  """)

  try db.execute(sql: """
    CREATE TRIGGER IF NOT EXISTS transcript_entries_ai
    AFTER INSERT ON transcript_entries BEGIN
      INSERT INTO transcript_entries_fts(rowid, content, entry_id, project_id)
      VALUES (new.rowid, new.content, new.id, new.project_id);
    END
  """)

  // Backfill existing entries
  try db.execute(sql: """
    INSERT INTO transcript_entries_fts(rowid, content, entry_id, project_id)
    SELECT rowid, content, id, project_id FROM transcript_entries
  """)
}
```

---

## Part 2: HooverEngine Updates (Window Tracking)

**Goal:** Precompute window SHA256 during ingestion for fast cache lookups.

### Window Computation

The window is the **previous 2 entry IDs** for better disposition detection:

```swift
// In KeyGeneration.swift
extension SHA256Utils {
  public static func computeWindowSHA256(prev2: String?, prev1: String?) -> String {
    let window = [prev2 ?? "", prev1 ?? ""].joined(separator: "|")
    return sha256(data: Data(window.utf8))
  }
}
```

### Update HooverEngine.commitBatch

Track previous entries per transcript and compute window:

```swift
private func commitBatch(
  transcriptId: String,
  entries: [EntryInsert],
  errors: [(lineNumber: Int, rawLine: String, error: String)],
  lastProcessedLine: Int,
  lineCount: Int,
  previousEntries: inout [String] // Track last 2 entry IDs
) throws {
  try db.write { db in
    // Insert entries with window tracking
    for entry in entries {
      // Compute window from previous 2 entries
      let prev1 = previousEntries.last
      let prev2 = previousEntries.count >= 2 ? previousEntries[previousEntries.count - 2] : nil
      let windowSha = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)

      var model = entry.toModel()
      model.prev1Id = prev1
      model.prev2Id = prev2
      model.windowSha256 = windowSha

      try model.insert(db, onConflict: .ignore)

      // Update tracking (keep last 2)
      previousEntries.append(entry.id)
      if previousEntries.count > 2 {
        previousEntries.removeFirst()
      }
    }

    // ... rest of batch logic (errors, prune, checkpoint)
  }
}
```

### Update Models.swift

Add window fields to `TranscriptEntry`:

```swift
public struct TranscriptEntry: Codable, FetchableRecord, PersistableRecord {
  // ... existing fields ...

  public var prev1Id: String?
  public var prev2Id: String?
  public var windowSha256: String?

  // ... existing code ...
}
```

---

## Part 3: Orchestrator API (Final Surface)

Make orchestrator **non-main** and expose only what UI needs. Keep it simple and synchronous where possible—`DatabasePool` handles concurrency.

### Complete Public API

```swift
public final class TranscriptOrchestrator {
  // Remove @MainActor - this is a data layer component

  public init(dbManager: DatabaseManager = .shared) throws {
    // ... existing init ...
  }

  // MARK: - Projects

  public func getOrCreateProject(name: String?, rootPath: String, bookmark: Data? = nil) throws -> String {
    // Already implemented ✅
  }

  // MARK: - Discovery & Ingestion

  public func discoverTranscript(
    projectId: String,
    fileURL: URL,
    provider: String,
    providerSessionId: String?,
    startWatching: Bool = true,
    progress: IngestProgressSink? = nil
  ) throws {
    // Existing logic, but add metadata invalidation:
    let sha256 = try hooverEngine.hooverTranscript(...)

    // Check if metadata needs regeneration
    if let existing = try metadataRepo.get(transcriptId),
       existing.transcriptSha256 == sha256 {
      // Fresh, skip
    } else {
      // Mark for regeneration (don't block hoover)
      // Actual generation happens async in UI layer
    }
  }

  public func discoverTranscripts(
    projectId: String,
    transcriptFiles: [(url: URL, provider: String, sessionId: String?)],
    progress: IngestProgressSink? = nil
  ) throws {
    // Already implemented ✅
  }

  // MARK: - Listing

  public func listTranscripts(provider: String) throws -> [Transcript] {
    try transcriptRepo.byProject(projectId).filter { $0.provider == provider }
  }

  public func getTranscripts(forProject projectId: String) throws -> [Transcript] {
    // Already implemented ✅
  }

  // MARK: - Entries

  public func getEntries(forTranscript transcriptId: String, afterTimestamp: Int? = nil) throws -> [TranscriptEntry] {
    // Already implemented ✅
  }

  public func getRecentEntries(forProject projectId: String, limit: Int = 50) throws -> [TranscriptEntry] {
    // Already implemented ✅ (filters display_in_timeline = 1, ORDER BY timestamp DESC)
  }

  public func getNewEntries(forProject projectId: String, afterTimestamp: Int) throws -> [TranscriptEntry] {
    // Already implemented ✅
  }

  // MARK: - Cache (Batched Operations)

  public func getCachedTimeline(contentSha256: String, windowSha256: String) throws -> TimelineCache? {
    // Already implemented ✅
  }

  public func getCachedTimelineMany(keys: [(String, String)]) throws -> [String: TimelineCache] {
    // NEW: Batched cache lookup
    guard !keys.isEmpty else { return [:] }

    let args = keys.flatMap { [$0.0, $0.1] }
    let placeholders = Array(repeating: "(?, ?)", count: keys.count).joined(separator: ",")

    return try cacheRepo.db.read { db in
      let sql = """
        SELECT * FROM timeline_cache
        WHERE (content_sha256, window_sha256) IN (\(placeholders))
      """
      let rows = try TimelineCache.fetchAll(db, sql: sql, arguments: StatementArguments(args))

      var result: [String: TimelineCache] = [:]
      for row in rows {
        let key = "\(row.contentSha256)|\(row.windowSha256)"
        result[key] = row
      }
      return result
    }
  }

  public func saveCachedTimeline(_ cache: TimelineCache) throws {
    // Already implemented ✅
  }

  // MARK: - Metadata

  public func getMetadata(forTranscript transcriptId: String) throws -> TranscriptMetadataRecord? {
    // Already implemented ✅
  }

  public func upsertMetadata(_ metadata: TranscriptMetadataRecord) throws {
    try metadataRepo.upsert(metadata)
  }

  // MARK: - Maintenance

  public func performMaintenance() throws {
    // Already implemented ✅
  }

  public func stopAllWatchers() {
    // Already implemented ✅
  }
}
```

---

## Part 4: Fast Timeline Loading (Single Query)

**Problem:** Per-row cache lookups create N+1 query problem.

**Solution:** LEFT JOIN cache in single query using precomputed window fields.

### Repository Method (Single Round Trip)

```swift
// In EntryRepositoryImpl
public func recentFeed(projectId: String, limit: Int) throws -> [(TranscriptEntry, TimelineCache?)] {
  try db.read { db in
    let sql = """
      SELECT
        e.*,
        c.present_form,
        c.past_form,
        c.selected_form,
        c.disposition,
        c.verb_lemma,
        c.user_edited,
        c.user_text
      FROM transcript_entries e
      LEFT JOIN timeline_cache c
        ON c.content_sha256 = e.content_sha256
       AND c.window_sha256  = e.window_sha256
      WHERE e.project_id = ?
        AND e.display_in_timeline = 1
      ORDER BY e.timestamp DESC
      LIMIT ?
    """

    return try Row.fetchAll(db, sql: sql, arguments: [projectId, limit]).map { row in
      let entry = TranscriptEntry(row: row)

      // Check if cache fields present
      let cache: TimelineCache? = if row["present_form"] != nil {
        TimelineCache(
          contentSha256: entry.contentSha256,
          windowSha256: entry.windowSha256!,
          entryId: entry.id,
          generatorSignature: "", // Not needed for display
          disposition: row["disposition"] as? String ?? "active",
          presentForm: row["present_form"] as? String ?? "",
          pastForm: row["past_form"] as? String ?? "",
          selectedForm: row["selected_form"] as? String ?? "present",
          verbLemma: row["verb_lemma"] as? String,
          generatedAt: 0,
          userEdited: row["user_edited"] as? Int ?? 0,
          userText: row["user_text"] as? String,
          editedAt: nil,
          requestId: nil,
          duration: nil
        )
      } else {
        nil
      }

      return (entry, cache)
    }
  }
}
```

### Add to EntryRepository Protocol

```swift
public protocol EntryRepository {
  // ... existing methods ...

  func recentFeed(projectId: String, limit: Int) throws -> [(TranscriptEntry, TimelineCache?)]
}
```

### Expose in Orchestrator

```swift
public func getRecentFeed(forProject projectId: String, limit: Int = 50) throws -> [(TranscriptEntry, TimelineCache?)] {
  try entryRepo.recentFeed(projectId: projectId, limit: limit)
}
```

---

## Part 5: UI Mapping (ConversationMonitor Integration)

### Convert SQL Entry to TimelineEntry

```swift
// In ConversationMonitor.swift
private func toTimelineEntry(_ entry: TranscriptEntry, cached: TimelineCache?) -> TimelineEntry {
  // Use cached summary if available, otherwise fallback
  let summary: String
  if let cache = cached {
    summary = cache.selectedForm == "present" ? cache.presentForm : cache.pastForm
  } else {
    // Fallback for cache miss (will trigger LLM generation)
    summary = String(entry.content.prefix(100)) + (entry.content.count > 100 ? "…" : "")
  }

  let disposition = cached.flatMap { Disposition(rawValue: $0.disposition) } ?? .active

  return TimelineEntry(
    id: UUID(uuidString: entry.id) ?? UUID(),
    kind: TimelineEntryKind(rawValue: entry.kind) ?? .assistant,
    timestamp: Date(timeIntervalSince1970: TimeInterval(entry.timestamp)),
    summary: summary,
    detail: entry.content,
    sourceContent: entry.content,
    sourceContext: TimelineSourceContext(
      provider: TimelineSourceContext.Provider(rawValue: entry.provider) ?? .other,
      identifier: entry.id,
      filePath: nil, // No longer relevant
      line: nil
    ),
    sourceIdentifier: entry.id,
    isCompletion: entry.isCompletion == 1,
    isDirective: entry.isDirective == 1,
    requestId: nil, // TODO: Add to schema if needed
    action: .none,
    sessionId: entry.sessionId
  )
}
```

### Load Feed on Startup

```swift
// In ConversationMonitor.swift
func startMonitoring(projectId: String) async throws {
  guard !isMonitoring else { return }
  log.info("Starting SQL-based timeline monitoring")

  self.currentProjectId = projectId
  isMonitoring = true

  // Load initial feed from SQL
  await loadFeedFromSQL()

  // Subscribe to realtime updates
  setupSQLNotifications()
}

private func loadFeedFromSQL() async {
  guard let projectId = currentProjectId else { return }

  isProcessing = true
  defer { isProcessing = false }

  do {
    // Single query gets entries + cache
    let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
    let feed = try orchestrator.getRecentFeed(forProject: projectId, limit: config.maxEntries)

    // Map to UI entries
    self.entries = feed.map { toTimelineEntry($0.0, cached: $0.1) }

    // Track latest timestamp for incremental updates
    if let latest = entries.first {
      lastSeenTimestamp = Int(latest.timestamp.timeIntervalSince1970)
    }

    lastUpdate = Date()
    lastError = nil

    log.info("Loaded \(entries.count) entries from SQL feed")
  } catch {
    lastError = "Failed to load timeline: \(error.localizedDescription)"
    log.error("SQL feed load failed: \(error.localizedDescription, privacy: .public)")
  }
}
```

### Realtime Updates via Notifications

```swift
private func setupSQLNotifications() {
  NotificationCenter.default.addObserver(
    forName: NSNotification.Name("TranscriptUpdated"),
    object: nil,
    queue: .main
  ) { [weak self] notification in
    Task { @MainActor [weak self] in
      await self?.handleTranscriptUpdate(notification)
    }
  }
}

private func handleTranscriptUpdate(_ notification: Notification) async {
  guard let projectId = currentProjectId,
        let lastTimestamp = lastSeenTimestamp else { return }

  do {
    let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
    let newEntries = try orchestrator.getNewEntries(
      forProject: projectId,
      afterTimestamp: lastTimestamp
    )

    guard !newEntries.isEmpty else { return }

    // Convert to timeline entries (no cache initially)
    let timelineEntries = newEntries.map { toTimelineEntry($0, cached: nil) }

    // Append to feed
    entries.append(contentsOf: timelineEntries)

    // Trim to max size
    if entries.count > config.maxEntries {
      entries = Array(entries.suffix(config.maxEntries))
    }

    // Update timestamp
    if let latest = newEntries.last {
      lastSeenTimestamp = latest.timestamp
    }

    lastUpdate = Date()

    log.debug("Added \(newEntries.count) new entries from SQL")
  } catch {
    log.error("Failed to fetch new entries: \(error.localizedDescription, privacy: .public)")
  }
}
```

---

## Part 6: Cache Writes (No JSON Files)

When generating LLM summaries, write directly to SQL:

### Generator Signature Helper

```swift
// In TimelineCacheOrchestrator or similar
private func generatorSignature() -> String {
  // Centralize and bump when prompt/model changes
  struct GeneratorSignature {
    let model: String
    let modelVersion: String
    let prompt: String
    let promptVersion: String

    var string: String {
      "\(model)@\(modelVersion)::\(prompt)@\(promptVersion)"
    }
  }

  return GeneratorSignature(
    model: "gpt-4o",
    modelVersion: "2025-09",
    prompt: "timeline",
    promptVersion: "3"
  ).string
}
```

### Save Generated Cache

```swift
func saveGeneratedSummary(
  entry: TranscriptEntry,
  result: FoundationLLM.TimelineSummaryResult
) async throws {

  let cache = TimelineCache(
    contentSha256: entry.contentSha256,
    windowSha256: entry.windowSha256 ?? "", // Should always be set by hoover
    entryId: entry.id,
    generatorSignature: generatorSignature(),
    disposition: result.disposition.rawValue,
    presentForm: result.presentForm,
    pastForm: result.pastForm,
    selectedForm: result.disposition == .completion ? "past" : "present",
    verbLemma: result.verbLemma,
    generatedAt: Int(Date().timeIntervalSince1970),
    userEdited: 0,
    userText: nil,
    editedAt: nil,
    requestId: nil, // TODO: Add if needed
    duration: result.duration
  )

  let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
  try orchestrator.saveCachedTimeline(cache)

  log.debug("Saved cache to SQL for entry \(entry.id)")
}
```

**Invalidation Policy:** Cache naturally misses when signature changes (we don't rewrite rows; we overwrite on upsert when new forms generated). Don't overthink this.

---

## Part 7: Metadata Invalidation (Wire It Now)

### After Hoover Completion

```swift
// In TranscriptOrchestrator.discoverTranscript
public func discoverTranscript(
  projectId: String,
  fileURL: URL,
  provider: String,
  providerSessionId: String?,
  startWatching: Bool = true,
  progress: IngestProgressSink? = nil
) throws {
  // ... existing upsert and get transcript ...

  // Hoover and get SHA256
  let transcriptSHA256 = try hooverEngine.hooverTranscript(
    transcript,
    fileURL: fileURL,
    progress: progressSink
  )

  // Check metadata freshness
  if let existing = try metadataRepo.get(transcriptId),
     existing.transcriptSha256 == transcriptSHA256 {
    log.debug("Metadata is fresh for \(transcriptId)")
  } else {
    // Mark stale - UI will regenerate asynchronously
    log.info("Metadata stale for \(transcriptId), needs regeneration")
    // Note: Actual generation happens in UI layer to avoid blocking hoover
  }

  // Start watching if requested
  if startWatching {
    try watcher.watch(transcriptId: transcriptId, fileURL: fileURL)
  }

  log.info("Discovered and hoovered transcript: \(transcriptId), SHA256: \(transcriptSHA256)")
}
```

### Metadata Generation (From SQL Entries)

```swift
// In TranscriptMetadataOrchestrator or similar
func generateMetadata(transcriptId: String, transcriptSHA256: String) async throws -> TranscriptMetadataRecord {
  // Get entries from SQL (not files)
  let orchestrator = try TranscriptOrchestrator(dbManager: .shared)
  let entries = try orchestrator.getEntries(forTranscript: transcriptId, afterTimestamp: nil)

  // Convert to Exchange format for LLM
  let exchanges = entries.map { entry in
    Exchange(
      role: Exchange.Role(rawValue: entry.kind) ?? .assistant,
      text: entry.content,
      timestamp: Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
    )
  }

  // Build context and call LLM
  let context = try builder.build(exchanges: exchanges, strategy: .adaptive, budgetTokens: 8000)
  let guided = try await llm.singlePass(context: context.text, sampledCount: context.sampledCount, totalCount: exchanges.count)

  // Create metadata record
  let metadata = TranscriptMetadataRecord(
    transcriptId: transcriptId,
    projectId: entries.first?.projectId ?? "",
    title: guided.title,
    description: guided.description,
    topics: try JSONEncoder().encode(guided.topics),
    confidence: guided.confidence,
    mayContainHallucinations: guided.needsReview ? 1 : 0,
    needsReview: guided.needsReview ? 1 : 0,
    generatedAt: Int(Date().timeIntervalSince1970),
    model: "gpt-4o",
    promptVersion: 2,
    generatorVersion: 1,
    transcriptSha256: transcriptSHA256, // Store SHA for freshness check
    messageCount: entries.count,
    strategy: "singlePass:adaptive",
    llmCalls: 1,
    latencyMs: 0, // TODO: Track
    createdAt: Int(Date().timeIntervalSince1970),
    updatedAt: Int(Date().timeIntervalSince1970)
  )

  // Save to SQL
  try orchestrator.upsertMetadata(metadata)

  return metadata
}
```

---

## Part 8: Watcher Semantics (Clean & Safe)

### Enhanced Notification Payload

```swift
// In TranscriptWatcher.swift
struct TranscriptUpdate: Codable {
  let transcriptId: String
  let maxTimestamp: Int
  let addedCount: Int
}

private func processFileChange(transcriptId: String, fileURL: URL) {
  watcherQueue.async { [weak self] in
    guard let self else { return }

    do {
      guard let transcript = try self.transcriptRepo.get(transcriptId) else { return }

      let beforeCount = (try? self.entryRepo.byTranscript(transcriptId, afterTimestamp: nil).count) ?? 0

      _ = try self.hooverEngine.hooverTranscript(transcript, fileURL: fileURL, progress: NoOpProgressSink())

      let afterCount = (try? self.entryRepo.byTranscript(transcriptId, afterTimestamp: nil).count) ?? 0
      let addedCount = afterCount - beforeCount

      // Get max timestamp for incremental queries
      let maxTimestamp = (try? self.entryRepo.byTranscript(transcriptId, afterTimestamp: nil).last?.timestamp) ?? 0

      // Post notification on main with update info
      DispatchQueue.main.async {
        let update = TranscriptUpdate(
          transcriptId: transcriptId,
          maxTimestamp: maxTimestamp,
          addedCount: addedCount
        )

        NotificationCenter.default.post(
          name: NSNotification.Name("TranscriptUpdated"),
          object: update
        )
      }

      self.log.debug("File change processed: \(transcriptId), added \(addedCount) entries")
    } catch {
      self.log.error("Failed to process file change: \(error.localizedDescription)")
    }
  }
}
```

---

## Part 9: Deleted Transcript Reconciliation

### Startup Reconciliation

```swift
// In TranscriptOrchestrator or TimelineIntegration
func reconcileDeletedTranscripts(projectId: String) throws {
  let transcripts = try transcriptRepo.byProject(projectId)

  for transcript in transcripts where transcript.status == "active" {
    if !FileManager.default.fileExists(atPath: transcript.filePath) {
      log.warning("Transcript file deleted: \(transcript.filePath)")

      try transcriptRepo.setIngestionState(
        id: transcript.id,
        lastProcessedLine: transcript.lastProcessedLine,
        lineCount: transcript.lineCount,
        parserVersion: transcript.parserVersion,
        status: "unavailable",
        lastError: "File deleted or moved"
      )
    }
  }
}
```

### Call on Startup

```swift
// In TimelineIntegration.startMonitoring
func startMonitoring() async throws {
  // ... existing setup ...

  // Reconcile deleted files
  try orchestrator.reconcileDeletedTranscripts(projectId: projectId)

  // ... continue with normal startup ...
}
```

---

## Part 10: Search (FTS5 When Ready)

### Add Search Methods to Repository

```swift
// In EntryRepositoryImpl
public func searchFTS(query: String, projectId: String?) throws -> [TranscriptEntry] {
  try db.read { db in
    var sql = """
      SELECT e.*
      FROM transcript_entries e
      JOIN transcript_entries_fts fts ON fts.entry_id = e.id
      WHERE fts MATCH ?
    """

    var args: [DatabaseValueConvertible] = [query]

    if let projectId = projectId {
      sql += " AND e.project_id = ?"
      args.append(projectId)
    }

    sql += " ORDER BY e.timestamp DESC LIMIT 100"

    return try TranscriptEntry.fetchAll(db, sql: sql, arguments: StatementArguments(args))
  }
}
```

### Fallback to LIKE

Keep existing LIKE-based search as fallback until FTS5 migration runs.

---

## Part 11: Indices That Actually Matter

### Already Done ✅

- `timeline_cache` WITHOUT ROWID
- Completion index with `timestamp DESC`
- Base project/transcript indexes

### Add in v2 Migration

- `idx_entries_feed_cover(project_id, timestamp, content_sha256, window_sha256) WHERE display_in_timeline = 1`

### Post-Hoover Optimization

```swift
// In TranscriptOrchestrator.performMaintenance
public func performMaintenance() throws {
  log.info("Running database maintenance...")

  // Check WAL size
  try dbManager.checkWALSize()

  // Run ANALYZE for query planner
  try dbManager.analyze()

  // Vacuum if needed
  try dbManager.vacuumIfNeeded()

  log.info("Database maintenance completed")
}
```

Call after initial bulk hoover:

```swift
// After discoverTranscripts completes
try orchestrator.performMaintenance()
```

---

## Part 12: ConversationMonitor Glue (What to Change)

### Delete All Legacy Code

**Remove these files entirely:**
- `TimelineCacheStore.swift`
- `TranscriptMetadataStore.swift` (keep struct, delete file operations)
- Any direct JSONL parsing in UI path
- Filesystem watchers in `ConversationMonitor`

**Remove these methods from ConversationMonitor:**
- `processConversationFile()` (lines 455-562)
- `processConversationEntry()` (lines 564-583)
- `processClaudeCodeEntry()` (lines 585-628)
- `processCodexEntry()` (lines 630-689)
- `configureFileWatcher()` (lines 273-304)
- `tearDownFileWatcher()` (lines 306-315)

### New Startup Flow

```swift
// In ConversationMonitor.swift
func startMonitoring() async {
  guard !isMonitoring else { return }

  // 1. Get project from HUD
  guard let projectRoot = HUDViewModel.shared.projectRootURL else {
    lastError = "No project root set"
    return
  }

  // 2. Get or create project in SQL
  do {
    let orchestrator = try TranscriptOrchestrator(dbManager: .shared)

    currentProjectId = try orchestrator.getOrCreateProject(
      name: projectRoot.lastPathComponent,
      rootPath: projectRoot.path
    )

    // 3. Background discover + hoover of new transcripts
    Task.detached(priority: .userInitiated) {
      try await self.discoverNewTranscripts(projectId: currentProjectId!, orchestrator: orchestrator)
    }

    // 4. Load initial feed (fast - single query)
    await loadFeedFromSQL()

    // 5. Subscribe to realtime updates
    setupSQLNotifications()

    isMonitoring = true
    log.info("SQL-based timeline monitoring started")
  } catch {
    lastError = "Failed to start monitoring: \(error.localizedDescription)"
    log.error("Monitoring startup failed: \(error.localizedDescription, privacy: .public)")
  }
}
```

### Background Discovery

```swift
private func discoverNewTranscripts(projectId: String, orchestrator: TranscriptOrchestrator) async throws {
  // Find JSONL files on disk
  guard let projectRoot = HUDViewModel.shared.projectRootURL else { return }

  let claudeDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/projects")

  let filesOnDisk = try FileManager.default.contentsOfDirectory(
    at: claudeDir,
    includingPropertiesForKeys: [.contentModificationDateKey],
    options: [.skipsHiddenFiles]
  ).filter { $0.pathExtension == "jsonl" }

  // Get files already in SQL
  let filesInSQL = Set(try orchestrator.getTranscripts(forProject: projectId).map { $0.filePath })

  // Find new files
  let newFiles = filesOnDisk.filter { !filesInSQL.contains($0.path) }

  guard !newFiles.isEmpty else {
    log.info("No new transcripts to discover")
    return
  }

  log.info("Discovering \(newFiles.count) new transcripts")

  // Batch discover with progress
  let files = newFiles.map { (url: $0, provider: "claude.code", sessionId: nil) }
  let progress = LoggingProgressSink(log: log)

  try orchestrator.discoverTranscripts(
    projectId: projectId,
    transcriptFiles: files,
    progress: progress
  )

  // Run maintenance after bulk ingest
  try orchestrator.performMaintenance()

  log.info("Discovery complete, refreshing feed")

  // Refresh feed on main
  await MainActor.run {
    Task { await self.loadFeedFromSQL() }
  }
}
```

---

## Part 13: Tests (Lean & Pointed)

### Add These Tests to IntegrationTests.swift

```swift
func testWindowFieldsComputed() throws {
  // Create project and transcript
  let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

  let transcriptPath = tempDir.appendingPathComponent("test.jsonl")
  let mockTranscript = """
  {"uuid":"msg-1","type":"user","timestamp":"2025-10-11T12:00:00.000Z","sessionId":"s1","message":{"role":"user","content":"First"}}
  {"uuid":"msg-2","type":"assistant","timestamp":"2025-10-11T12:00:01.000Z","sessionId":"s1","message":{"role":"assistant","content":"Second"}}
  {"uuid":"msg-3","type":"user","timestamp":"2025-10-11T12:00:02.000Z","sessionId":"s1","message":{"role":"user","content":"Third"}}
  """
  try mockTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)

  let transcriptId = try transcriptRepo.upsert(projectId: projectId, fileURL: transcriptPath, provider: "claude.code", providerSessionId: "s1", lastModified: Date(), fileSize: 100)
  let transcript = try transcriptRepo.get(transcriptId)!

  // Hoover
  _ = try hooverEngine.hooverTranscript(transcript, fileURL: transcriptPath, progress: NoOpProgressSink())

  // Check window fields
  let entries = try entryRepo.byTranscript(transcriptId, afterTimestamp: nil)
  XCTAssertEqual(entries.count, 3)

  // First entry has no context
  XCTAssertNil(entries[0].prev1Id)
  XCTAssertNil(entries[0].prev2Id)
  XCTAssertNotNil(entries[0].windowSha256) // Should be hash of empty context

  // Second entry has 1 context
  XCTAssertEqual(entries[1].prev1Id, entries[0].id)
  XCTAssertNil(entries[1].prev2Id)
  XCTAssertNotNil(entries[1].windowSha256)

  // Third entry has 2 context
  XCTAssertEqual(entries[2].prev1Id, entries[1].id)
  XCTAssertEqual(entries[2].prev2Id, entries[0].id)
  XCTAssertNotNil(entries[2].windowSha256)
}

func testFeedCacheJoinSingleQuery() throws {
  // Setup project with entries and cache
  let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

  // ... create transcript and entries ...

  // Save cache for one entry
  let cache = TimelineCache(
    contentSha256: entries[0].contentSha256,
    windowSha256: entries[0].windowSha256!,
    entryId: entries[0].id,
    generatorSignature: "test",
    disposition: "active",
    presentForm: "Test present",
    pastForm: "Test past",
    selectedForm: "present",
    verbLemma: "test",
    generatedAt: Int(Date().timeIntervalSince1970),
    userEdited: 0,
    userText: nil,
    editedAt: nil,
    requestId: nil,
    duration: nil
  )
  try cacheRepo.upsert(cache)

  // Query feed (single query with join)
  let feed = try entryRepo.recentFeed(projectId: projectId, limit: 10)

  XCTAssertEqual(feed.count, entries.count)
  XCTAssertNotNil(feed[0].1, "First entry should have cache")
  XCTAssertEqual(feed[0].1?.presentForm, "Test present")
}

func testDeletedTranscriptsMarkedUnavailable() throws {
  let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

  let transcriptPath = tempDir.appendingPathComponent("test.jsonl")
  try "test".write(to: transcriptPath, atomically: true, encoding: .utf8)

  let transcriptId = try transcriptRepo.upsert(projectId: projectId, fileURL: transcriptPath, provider: "claude.code", providerSessionId: "s1", lastModified: Date(), fileSize: 4)

  // Delete file
  try FileManager.default.removeItem(at: transcriptPath)

  // Run reconciliation
  try orchestrator.reconcileDeletedTranscripts(projectId: projectId)

  // Check status
  let transcript = try transcriptRepo.get(transcriptId)
  XCTAssertEqual(transcript?.status, "unavailable")
  XCTAssertEqual(transcript?.lastError, "File deleted or moved")
}
```

---

## Part 14: Removal Checklist

### Files to Delete Entirely

- [ ] `Contextify/Contextify/TimelineCacheStore.swift`
- [ ] `Contextify/Contextify/TranscriptMetadataStore.swift`

### Methods to Remove from ConversationMonitor.swift

- [ ] `processConversationFile()` (lines 455-562)
- [ ] `processConversationEntry()` (lines 564-583)
- [ ] `processClaudeCodeEntry()` (lines 585-628)
- [ ] `processCodexEntry()` (lines 630-689)
- [ ] `processUserMessage()` (lines 691-809)
- [ ] `processAssistantMessage()` (lines 811-845)
- [ ] `addAssistantTextEntry()` (lines 847-943)
- [ ] `configureFileWatcher()` (lines 273-304)
- [ ] `tearDownFileWatcher()` (lines 306-315)

### Properties to Remove

- [ ] `fileWatcher: DispatchSourceFileSystemObject?`
- [ ] `conversationFileDescriptor: CInt`
- [ ] `lastProcessedLine: Int`
- [ ] `currentLineNumber: Int`
- [ ] `seenMessageUUIDs: Set<String>`
- [ ] `currentConversationFile: URL?`

### Grep Commands

```bash
# Find direct JSONL reads
rg "String\(contentsOf:.*\.jsonl" --type swift

# Find filesystem watchers
rg "DispatchSource\.makeFileSystemObjectSource" --type swift

# Find sidecar metadata references
rg "\.metadata\.json" --type swift

# Find cache file references
rg "TimelineCache.*Application Support" --type swift

# Find transcript parser direct usage (should only be in HooverEngine)
rg "TranscriptParser\(\)" --type swift
```

---

## Part 15: Logging Standards

### Use Consistent Levels

```swift
// Milestones
log.info("Starting SQL-based timeline monitoring")
log.info("Loaded \(count) entries from SQL feed")
log.info("Hoovered \(lines) lines in \(ms)ms (\(lps) lines/sec)")

// Routine operations (hidden in production with TYPE Info filter)
log.debug("Querying recent entries for project \(projectId)")
log.debug("Converting entry \(id) to TimelineEntry")
log.debug("Cache hit for \(contentSha)|\(windowSha)")

// Performance warnings
log.warning("LLM generation took \(duration)ms (>500ms threshold)")
log.warning("Cache miss rate high: \(missRate)% (target: <20%)")

// Failures requiring user action
log.error("Failed to load entries from SQL: \(error)")
log.error("Database migration failed: \(error)")
```

---

## Part 16: What's Already Fixed ✅

- timeline_cache WITHOUT ROWID
- Completion index with timestamp DESC
- EOF partial-line bug
- Hoover returns transcript_sha256
- Watcher off main + stopAll iteration fix
- MetadataRepository.stale OR filter fix
- Import order cleanup
- Path canonicalization
- Single-transaction batching
- getOrCreateProject helper
- Entry query methods (newByProject, insert)

---

## Part 17: Implementation Order

### Phase 1: Schema & Data Layer (This Branch)

1. ✅ Add DatabaseMigrator with v2 migration (window fields + covering index)
2. ✅ Update Models.swift with window fields
3. ✅ Update HooverEngine.commitBatch to track and persist window
4. ✅ Add recentFeed() method to EntryRepository
5. ✅ Add getCachedTimelineMany() to Orchestrator
6. ✅ Add reconcileDeletedTranscripts() to Orchestrator
7. ✅ Update TranscriptWatcher notification payload

### Phase 2: UI Integration (New Branch After Merge)

1. Delete legacy files (TimelineCacheStore, SidecarMetadataStore operations)
2. Remove file parsing from ConversationMonitor
3. Implement loadFeedFromSQL() with single-query join
4. Implement handleTranscriptUpdate() with incremental query
5. Wire startMonitoring() to SQL path
6. Implement background discovery
7. Update TimelineIntegration to call SQL methods
8. Remove all filesystem watchers

### Phase 3: Testing & Validation

1. Add integration tests for window fields
2. Add test for feed+cache join
3. Add test for deleted transcript reconciliation
4. Manual testing checklist
5. Performance validation (feed load < 1s for 500 entries)
6. Memory profiling (flat with pagination)

### Phase 4: Cleanup & Documentation

1. Run keyword sweep
2. Remove deprecated code
3. Update README.md
4. Update CLAUDE.md
5. Final build and validation

---

## Part 18: Success Criteria

**Timeline populates from SQL queries:** ✅ Single query with LEFT JOIN cache
**Cache stored in SQL:** ✅ No JSON files
**Metadata stored in SQL:** ✅ No sidecar files
**All UI features work:** ✅ Feed, updates, search
**Performance targets met:** ✅ <1s feed load, <5ms cache lookup
**Legacy code removed:** ✅ No file-based parsing in UI path
**Tests passing:** ✅ Integration tests + manual checklist
**Database optimized:** ✅ ANALYZE run, WAL managed

---

## Appendix A: SQL Query Reference

### Feed with Cache (Single Query)

```sql
SELECT
  e.*,
  c.present_form,
  c.past_form,
  c.selected_form,
  c.disposition,
  c.verb_lemma
FROM transcript_entries e
LEFT JOIN timeline_cache c
  ON c.content_sha256 = e.content_sha256
 AND c.window_sha256  = e.window_sha256
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC
LIMIT ?;
```

### Incremental Updates

```sql
SELECT e.*, c.present_form, c.past_form, c.selected_form, c.disposition
FROM transcript_entries e
LEFT JOIN timeline_cache c
  ON c.content_sha256 = e.content_sha256
 AND c.window_sha256  = e.window_sha256
WHERE e.project_id = ?
  AND e.timestamp > ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp ASC;
```

### Batched Cache Lookup

```sql
SELECT * FROM timeline_cache
WHERE (content_sha256, window_sha256) IN ((?,?),(?,?),(?,?));
```

### FTS5 Search

```sql
SELECT e.*
FROM transcript_entries e
JOIN transcript_entries_fts fts ON fts.entry_id = e.id
WHERE fts MATCH ?
  AND e.project_id = ?
ORDER BY e.timestamp DESC
LIMIT 100;
```

---

## Appendix B: Code Snippets

### DatabaseMigrator Setup

```swift
// In DatabaseSchema.swift
public static func createMigrator() -> DatabaseMigrator {
  var migrator = DatabaseMigrator()

  migrator.registerMigration("v1_base") { db in
    try migrate(db) // Existing schema
  }

  migrator.registerMigration("v2_window_sha") { db in
    try db.alter(table: "transcript_entries") { t in
      t.add(column: "prev1_id", .text)
      t.add(column: "prev2_id", .text)
      t.add(column: "window_sha256", .text)
    }

    try db.create(
      index: "idx_entries_feed_cover",
      on: "transcript_entries",
      columns: ["project_id", "timestamp", "content_sha256", "window_sha256"],
      condition: "display_in_timeline = 1",
      ifNotExists: true
    )
  }

  return migrator
}
```

### Window Computation in HooverEngine

```swift
private func commitBatch(
  transcriptId: String,
  entries: [EntryInsert],
  errors: [(lineNumber: Int, rawLine: String, error: String)],
  lastProcessedLine: Int,
  lineCount: Int,
  previousEntries: inout [String]
) throws {
  try db.write { db in
    for entry in entries {
      let prev1 = previousEntries.last
      let prev2 = previousEntries.count >= 2 ? previousEntries[previousEntries.count - 2] : nil
      let windowSha = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)

      var model = entry.toModel()
      model.prev1Id = prev1
      model.prev2Id = prev2
      model.windowSha256 = windowSha

      try model.insert(db, onConflict: .ignore)

      previousEntries.append(entry.id)
      if previousEntries.count > 2 {
        previousEntries.removeFirst()
      }
    }

    // ... rest of batch logic
  }
}
```

---

## End of Document

**Next Actions:**
1. Commit this v2 plan to `feature/sqlite-backend-migration`
2. Commit existing SQL work (getOrCreateProject, entry query methods)
3. Merge `feature/sqlite-backend-migration` to `main`
4. Create new branch `feature/sql-cutover-implementation`
5. Implement Phase 1 (schema & data layer)
6. Implement Phase 2 (UI integration)
7. Test and validate
8. Merge and ship

**Estimated Implementation Time:** 12-16 hours (1.5-2 engineering days)
