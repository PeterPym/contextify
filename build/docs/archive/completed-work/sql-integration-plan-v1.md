# SQL Backend Integration Plan v1

**Status:** Implementation Plan
**Created:** 2025-10-11
**Context:** The SQL backend is complete and tested (see `sql-implementation-plan-05.md`), but not integrated with the existing UI/timeline system.

## Executive Summary

The current Contextify system has **two parallel data paths**:

1. **SQL Backend** (✅ Complete): `DatabaseManager`, `HooverEngine`, `TranscriptOrchestrator` - ingests transcripts into SQLite with streaming parser
2. **File-Based System** (🔄 Active): `ConversationMonitor`, `TimelineCacheStore`, `SidecarMetadataStore` - reads JSONL files directly, generates summaries, caches to JSON files

**Goal:** Replace the file-based system with SQL backend queries while preserving all UI functionality.

**Success Criteria:**
- Timeline populates from SQL queries, not direct file parsing
- Timeline cache stored in `timeline_cache` table, not JSON files
- Transcript metadata stored in `transcript_metadata` table, not sidecar `.metadata.json` files
- All existing UI features work identically
- Performance meets or exceeds current system
- Old file-based code removed

---

## Part 1: System Architecture Analysis

### Current File-Based Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ ConversationMonitor (@MainActor @Observable)           │
│                                                         │
│ 1. Discovers transcript files (.jsonl)                 │
│ 2. Reads file directly with String(contentsOf:)        │
│ 3. Parses lines with JSONSerialization                 │
│ 4. Calls FoundationLLM.summarizeTimelineWithForms()    │
│ 5. Stores in visibleEntries: [TimelineEntry]          │
└─────────────────────────────────────────────────────────┘
                     │
                     ├──► TimelineCacheOrchestrator (actor)
                     │    - Loads/saves cache to JSON files
                     │    - Path: ~/Library/Application Support/Contextify/TimelineCache/
                     │
                     └──► TranscriptMetadataOrchestrator (actor)
                          - Loads/saves metadata to sidecar JSON files
                          - Path: {transcript}.metadata.json
```

### Target SQL-Based Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ ConversationMonitor (@MainActor @Observable)           │
│                                                         │
│ 1. Queries TranscriptOrchestrator for entries          │
│ 2. Gets EntryRepository.byProject() from SQLite        │
│ 3. Checks TimelineCacheRepository for cached summaries │
│ 4. Generates summaries for cache misses (LLM call)     │
│ 5. Stores in visibleEntries: [TimelineEntry]          │
└─────────────────────────────────────────────────────────┘
                     │
                     ├──► TimelineCacheRepository
                     │    - SELECT/INSERT to timeline_cache table
                     │    - Composite PK: (content_sha256, window_sha256)
                     │
                     └──► MetadataRepository
                          - SELECT/INSERT to transcript_metadata table
                          - FK to transcripts table
```

---

## Part 2: Component-by-Component Integration Plan

### 2.1 ConversationMonitor.swift (Primary Integration Point)

**Current Behavior:**
- `processConversationFile()` reads JSONL files directly (line 300-450)
- Parses JSON with `JSONSerialization.jsonObject`
- Builds `TimelineEntry` structs from parsed records
- Calls `TimelineCacheOrchestrator.getCachedEntry()` for LLM summaries

**Required Changes:**

#### Change A: Replace File Reading with SQL Queries
```swift
// OLD (lines ~300-350):
private func processConversationFile() async {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)
    for line in lines {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        // ... parse logic
    }
}

// NEW:
private func loadEntriesFromSQL() async throws {
    guard let projectId = currentProjectId else { return }

    // Get entries from SQL backend
    let orchestrator = try await TranscriptOrchestrator.shared
    let entries = try await orchestrator.getRecentEntries(
        forProject: projectId,
        limit: config.maxEntries
    )

    // Convert TranscriptEntry -> TimelineEntry
    for entry in entries {
        let timelineEntry = await convertToTimelineEntry(entry)
        visibleEntries.append(timelineEntry)
    }
}
```

#### Change B: Convert TranscriptEntry to TimelineEntry
```swift
// NEW helper method:
private func convertToTimelineEntry(_ sqlEntry: TranscriptEntry) async -> TimelineEntry {
    // Check timeline cache for summary
    let cached = try? await orchestrator.getCachedTimeline(
        contentSha256: sqlEntry.contentSha256,
        windowSha256: computeWindowHash(for: sqlEntry)
    )

    let summary: String
    if let cached = cached {
        summary = cached.selectedForm == "present" ? cached.presentForm : cached.pastForm
    } else {
        // Cache miss - generate with LLM
        summary = try await generateSummary(for: sqlEntry)
    }

    return TimelineEntry(
        id: UUID(uuidString: sqlEntry.id) ?? UUID(),
        kind: TimelineEntryKind(rawValue: sqlEntry.kind) ?? .assistant,
        timestamp: Date(timeIntervalSince1970: TimeInterval(sqlEntry.timestamp)),
        summary: summary,
        detail: sqlEntry.content,
        sourceContent: sqlEntry.content,
        sourceContext: TimelineSourceContext(
            provider: TimelineSourceContext.Provider(rawValue: sqlEntry.provider) ?? .other,
            identifier: sqlEntry.id
        ),
        sourceIdentifier: sqlEntry.id,
        isCompletion: sqlEntry.isCompletion == 1,
        isDirective: sqlEntry.isDirective == 1,
        sessionId: sqlEntry.sessionId
    )
}
```

#### Change C: Remove File Watching, Use SQL Notifications
```swift
// OLD: DispatchSourceFileSystemObject watching JSONL files
// NEW: NotificationCenter observing "TranscriptUpdated" from TranscriptWatcher

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
    guard let transcriptId = notification.object as? String else { return }

    // Fetch new entries for this transcript
    let newEntries = try? await orchestrator.getEntries(
        forTranscript: transcriptId,
        afterTimestamp: lastSeenTimestamp
    )

    // Convert and append to timeline
    for entry in newEntries ?? [] {
        let timelineEntry = await convertToTimelineEntry(entry)
        visibleEntries.append(timelineEntry)
    }

    lastUpdate = Date()
}
```

#### Testing Steps for ConversationMonitor:
1. Start app, verify timeline populates from SQL (no file reads)
2. Open iTerm2, send message to Claude Code
3. Verify new entry appears in timeline within 2 seconds
4. Check logs for "Loaded X entries from SQL" (not "Parsed X lines from file")
5. Verify timeline cache hits/misses logged correctly

---

### 2.2 TimelineCacheOrchestrator.swift (Cache Layer Integration)

**Current Behavior:**
- Actor-based cache coordinator
- Stores cache in `~/Library/Application Support/Contextify/TimelineCache/`
- Uses `TimelineCacheStore` for file I/O
- Computes content/window hashes for cache keys

**Required Changes:**

#### Change A: Replace TimelineCacheStore with TimelineCacheRepository
```swift
// OLD (lines 12-16):
actor TimelineCacheOrchestrator {
    private let store: TimelineCacheStore
    private var cache: TimelineCache?
    private var conversationURL: URL?

    private init() {
        self.store = TimelineCacheStore()
    }
}

// NEW:
actor TimelineCacheOrchestrator {
    private let repo: TimelineCacheRepository
    private let db: DatabasePool

    private init() async throws {
        self.db = try await DatabaseManager.shared.pool
        self.repo = TimelineCacheRepositoryImpl(db: db)
    }
}
```

#### Change B: Replace File-Based Cache Lookups with SQL
```swift
// OLD (lines 82-108):
if let entry = cache.entries[messageUUID],
   entry.contentHash == contentHash,
   entry.windowHash == windowHash {
    // Cache HIT from in-memory dictionary
    return RenderedTimelineEntry(summary: entry.render(), ...)
}

// NEW:
func getCachedEntry(
    messageUUID: String,
    contentSha256: String,
    windowSha256: String
) async throws -> RenderedTimelineEntry? {

    // SQL query for cache hit
    let cached = try await repo.get(
        contentSha256: contentSha256,
        windowSha256: windowSha256
    )

    if let cached = cached {
        log.debug("Cache HIT from SQL for \(messageUUID, privacy: .public)")
        return RenderedTimelineEntry(
            summary: cached.selectedForm == "present" ? cached.presentForm : cached.pastForm,
            disposition: Disposition(rawValue: cached.disposition) ?? .active,
            isCompletion: false,
            isDirective: false,
            requestId: cached.requestId,
            duration: cached.duration
        )
    }

    // Cache MISS - caller must generate with LLM
    return nil
}
```

#### Change C: Save Cache to SQL Instead of JSON
```swift
// OLD (lines 192-203):
func persistCache() async throws {
    guard dirty, let cache = cache, let url = conversationURL else { return }
    try await store.save(cache, for: url)
}

// NEW:
func saveCache(
    entryId: String,
    contentSha256: String,
    windowSha256: String,
    llmResult: LLMSummaryResult
) async throws {

    let cache = TimelineCache(
        contentSha256: contentSha256,
        windowSha256: windowSha256,
        entryId: entryId,
        generatorSignature: generatorSignature(),
        disposition: llmResult.disposition.rawValue,
        presentForm: llmResult.presentForm,
        pastForm: llmResult.pastForm,
        selectedForm: llmResult.disposition == .completion ? "past" : "present",
        verbLemma: llmResult.verbLemma,
        generatedAt: Int(Date().timeIntervalSince1970),
        userEdited: 0,
        userText: nil,
        editedAt: nil,
        requestId: nil,
        duration: nil
    )

    try await repo.upsert(cache)
    log.debug("Saved cache to SQL for entry \(entryId, privacy: .public)")
}
```

#### Testing Steps for TimelineCacheOrchestrator:
1. Clear `timeline_cache` table: `DELETE FROM timeline_cache`
2. Load timeline, verify LLM calls for all entries (cache misses)
3. Reload timeline, verify cache hits from SQL (no LLM calls)
4. Check DB: `SELECT COUNT(*) FROM timeline_cache` should match entry count
5. Verify no JSON files created in `~/Library/Application Support/Contextify/TimelineCache/`

---

### 2.3 TranscriptMetadataOrchestrator.swift (Metadata Integration)

**Current Behavior:**
- Generates title/description/topics for transcript sessions
- Stores in sidecar files: `{transcript}.metadata.json`
- Uses `SidecarMetadataStore` for file I/O
- Checks SHA256 hash for cache freshness

**Required Changes:**

#### Change A: Replace SidecarMetadataStore with MetadataRepository
```swift
// OLD (lines 35-38):
actor TranscriptMetadataOrchestrator {
    private let store = SidecarMetadataStore()
    private let parser = TranscriptParser()
    // ...
}

// NEW:
actor TranscriptMetadataOrchestrator {
    private let repo: MetadataRepository
    private let db: DatabasePool

    private init() async throws {
        self.db = try await DatabaseManager.shared.pool
        self.repo = MetadataRepositoryImpl(db: db)
    }
}
```

#### Change B: Load Metadata from SQL
```swift
// OLD (lines 102-112):
if !forceRegenerate,
   let cached = try? store.load(for: session.fileURL),
   store.isFresh(cached, for: session.fileURL, ...) {
    return cached
}

// NEW:
func ensureMetadata(for transcriptId: String, forceRegenerate: Bool = false) async throws -> TranscriptMetadata {

    // Check SQL cache first
    if !forceRegenerate, let cached = try? await repo.get(transcriptId) {
        log.info("Using cached metadata from SQL for \(transcriptId, privacy: .public)")
        return cached
    }

    // Generate new metadata
    let metadata = try await generateMetadata(for: transcriptId)

    // Save to SQL
    try await repo.upsert(metadata)

    return metadata
}
```

#### Change C: Generate Metadata from SQL Entries (Not Files)
```swift
// OLD (lines 115-120):
let parseStart = Date()
let exchanges = try parser.parseExchanges(url: session.fileURL)
let parseTime = Date().timeIntervalSince(parseStart)

// NEW:
func generateMetadata(for transcriptId: String) async throws -> TranscriptMetadata {
    let parseStart = Date()

    // Get entries from SQL instead of parsing file
    let entries = try await orchestrator.getEntries(
        forTranscript: transcriptId,
        afterTimestamp: nil
    )

    // Convert TranscriptEntry -> Exchange for LLM context building
    let exchanges = entries.map { entry in
        Exchange(
            role: Exchange.Role(rawValue: entry.kind) ?? .assistant,
            text: entry.content,
            timestamp: Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
        )
    }

    let parseTime = Date().timeIntervalSince(parseStart)

    // Rest of generation logic unchanged...
    let context = try builder.build(exchanges: exchanges, strategy: .adaptive, budgetTokens: availableTokens)
    let guided = try await llm.singlePass(context: context.text, ...)

    // Save to SQL (see Change B above)
    let metadata = postProcessor.apply(to: guided, context: context.text)
    metadata.transcriptId = transcriptId
    metadata.messageCount = exchanges.count

    return metadata
}
```

#### Testing Steps for TranscriptMetadataOrchestrator:
1. Clear `transcript_metadata` table: `DELETE FROM transcript_metadata`
2. Open transcripts, verify metadata generation triggers
3. Check logs: should see "Generating metadata" (not "Parsing transcript file")
4. Verify DB: `SELECT * FROM transcript_metadata` should have records
5. Verify no `.metadata.json` sidecar files created next to transcripts

---

### 2.4 ConversationSources.swift (Session Discovery)

**Current Behavior:**
- Scans filesystem for `.jsonl` files
- Returns `TranscriptSession` structs with `fileURL`
- No SQL awareness

**Required Changes:**

#### Change A: Discover Sessions from SQL Instead of Files
```swift
// OLD (lines ~50-100):
func discoverClaudeSessions() -> [TranscriptSession] {
    let projectsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    let files = try? FileManager.default.contentsOfDirectory(at: projectsDir, ...)
        .filter { $0.pathExtension == "jsonl" }

    return files?.map { url in
        TranscriptSession(fileURL: url, provider: .claudeCode, ...)
    } ?? []
}

// NEW:
func discoverClaudeSessions() async throws -> [TranscriptSession] {
    // Query SQL for all Claude Code transcripts
    let orchestrator = try await TranscriptOrchestrator.shared
    let transcripts = try await orchestrator.listTranscripts(provider: "claude.code")

    return transcripts.map { transcript in
        TranscriptSession(
            id: transcript.id,
            fileURL: URL(fileURLWithPath: transcript.filePath),
            provider: .claudeCode,
            lastModified: Date(timeIntervalSince1970: TimeInterval(transcript.lastModified)),
            lineCount: transcript.lineCount,
            status: transcript.status
        )
    }
}
```

#### Change B: Initial Hoover for New Projects
```swift
// NEW method to discover and ingest transcripts on first launch:
func discoverAndHooverNewTranscripts(projectId: String) async throws {
    let orchestrator = try await TranscriptOrchestrator.shared

    // Find JSONL files on disk not yet in SQL
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    let filesOnDisk = try FileManager.default.contentsOfDirectory(at: claudeDir, ...)
        .filter { $0.pathExtension == "jsonl" }

    let filesInSQL = try await orchestrator.listTranscripts(provider: "claude.code")
        .map { URL(fileURLWithPath: $0.filePath) }

    let newFiles = filesOnDisk.filter { !filesInSQL.contains($0) }

    // Batch discover
    let progress = LoggingProgressSink(log: log)
    let files = newFiles.map { (url: $0, provider: "claude.code", sessionId: nil) }

    try await orchestrator.discoverTranscripts(
        projectId: projectId,
        transcriptFiles: files,
        progress: progress
    )
}
```

#### Testing Steps for ConversationSources:
1. Clear `transcripts` table: `DELETE FROM transcripts`
2. Launch app, verify `discoverAndHooverNewTranscripts()` runs
3. Check logs: should see "Hoovering transcript X of Y"
4. Verify DB: `SELECT COUNT(*) FROM transcripts` matches filesystem count
5. Verify timeline populates after hoover completes

---

### 2.5 TimelineIntegration.swift (System Coordinator)

**Current Behavior:**
- Singleton that starts `ConversationMonitor`
- Handles refresh triggers

**Required Changes:**

#### Change A: Initialize SQL Backend on Startup
```swift
// OLD (lines 14-21):
func startMonitoring() {
    guard !isActive else { return }
    log.info("Timeline integration starting")
    isActive = true
    ConversationMonitor.shared.startMonitoring()
    registerNotifications()
}

// NEW:
func startMonitoring() async throws {
    guard !isActive else { return }
    log.info("Timeline integration starting")

    // Initialize SQL backend
    let orchestrator = try await TranscriptOrchestrator.shared

    // Discover project root
    guard let projectRoot = HUDViewModel.shared.projectRoot else {
        throw IntegrationError.noProjectRoot
    }

    // Get or create project in SQL
    let projectId = try await orchestrator.getOrCreateProject(
        name: projectRoot.lastPathComponent,
        rootPath: projectRoot.path
    )

    // Initial hoover of new transcripts
    try await ConversationSources.shared.discoverAndHooverNewTranscripts(projectId: projectId)

    // Start real-time monitoring
    isActive = true
    await ConversationMonitor.shared.startMonitoring(projectId: projectId)
    registerNotifications()
}
```

#### Testing Steps for TimelineIntegration:
1. Delete `transcripts.db` to simulate fresh install
2. Launch app, verify project created in SQL
3. Verify initial hoover runs (check logs)
4. Verify timeline populates after startup
5. Send new message, verify timeline updates within 2 seconds

---

## Part 3: Data Migration Strategy

### 3.1 One-Time Migration (Optional)

**Goal:** Preserve existing timeline cache and metadata during transition.

**Approach:** Script to convert JSON files → SQL inserts.

```bash
#!/bin/bash
# migrate-cache-to-sql.sh

set -e

DB_PATH="$HOME/Library/Application Support/Contextify/transcripts.db"
CACHE_DIR="$HOME/Library/Application Support/Contextify/TimelineCache"

echo "Migrating timeline cache to SQL..."

# Parse Index.json and convert to SQL INSERTs
python3 << 'EOF'
import json
import sqlite3
import os
from pathlib import Path

db_path = os.path.expanduser("~/Library/Application Support/Contextify/transcripts.db")
cache_dir = os.path.expanduser("~/Library/Application Support/Contextify/TimelineCache")

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Find all entries.json files
for cache_file in Path(cache_dir).rglob("entries.json"):
    with open(cache_file) as f:
        cache_data = json.load(f)

    for entry_id, entry in cache_data.get("entries", {}).items():
        cursor.execute("""
            INSERT OR IGNORE INTO timeline_cache (
                content_sha256, window_sha256, entry_id, generator_signature,
                disposition, present_form, past_form, selected_form,
                verb_lemma, generated_at, user_edited, user_text, edited_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            entry["contentHash"],
            entry["windowHash"],
            entry_id,
            entry["generatorSignature"],
            entry["disposition"],
            entry["presentForm"],
            entry["pastForm"],
            entry["selectedForm"],
            entry.get("verbLemma"),
            int(entry["generatedAt"]),
            1 if entry.get("userEdited") else 0,
            entry.get("userText"),
            int(entry["editedAt"]) if entry.get("editedAt") else None
        ))

conn.commit()
print(f"Migrated {cursor.rowcount} cache entries")
conn.close()
EOF

echo "Migration complete!"
```

**Decision:** Migration is **optional**. Fresh cache generation is fast (<200ms per entry with LLM calls).

---

### 3.2 Fallback Strategy

**Problem:** If SQL integration has bugs, users lose timeline functionality.

**Solution:** Feature flag to toggle between file-based and SQL backends.

```swift
// Feature flag (UserDefaults)
enum TimelineBackend: String {
    case fileSystem = "filesystem"
    case sql = "sql"
}

@MainActor
final class TimelineIntegration {
    private var backend: TimelineBackend {
        UserDefaults.standard.string(forKey: "TimelineBackend")
            .flatMap { TimelineBackend(rawValue: $0) } ?? .sql
    }

    func startMonitoring() async throws {
        switch backend {
        case .fileSystem:
            log.warning("Using LEGACY file-based backend (fallback mode)")
            ConversationMonitor.shared.startMonitoringLegacy()
        case .sql:
            log.info("Using SQL backend")
            try await startSQLMonitoring()
        }
    }
}

// Enable fallback via defaults:
// defaults write dev.contextify.Contextify TimelineBackend filesystem
```

---

## Part 4: Testing Strategy

### 4.1 Unit Tests (New)

**File:** `Contextify/ContextifyTests/TimelineIntegrationTests.swift`

```swift
import XCTest
@testable import ContextifyCore

final class TimelineIntegrationTests: XCTestCase {
    var tempDir: URL!
    var db: DatabasePool!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let dbPath = tempDir.appendingPathComponent("test.db")
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabasePool(path: dbPath.path, configuration: config)
        try db.write { db in try DatabaseSchema.migrate(db) }
    }

    func testConvertSQLEntryToTimelineEntry() async throws {
        // Create test data
        let projectRepo = ProjectRepositoryImpl(db: db)
        let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

        let transcriptRepo = TranscriptRepositoryImpl(db: db)
        let transcriptId = try transcriptRepo.upsert(
            projectId: projectId,
            fileURL: URL(fileURLWithPath: "/test/transcript.jsonl"),
            provider: "claude.code",
            providerSessionId: "session-1",
            lastModified: Date(),
            fileSize: 1000
        )

        let entryRepo = EntryRepositoryImpl(db: db)
        let entry = TranscriptEntry(
            id: "msg-1",
            transcriptId: transcriptId,
            projectId: projectId,
            sessionId: "session-1",
            provider: "claude.code",
            kind: "user",
            timestamp: Int(Date().timeIntervalSince1970),
            content: "Hello, world!",
            contentSha256: "sha256:abc123",
            summary: nil,
            disposition: nil,
            displayInTimeline: 1,
            isCompletion: 0,
            isDirective: 0,
            parentId: nil,
            gitBranch: "main",
            gitCommit: nil,
            cwd: "/test",
            createdAt: Int(Date().timeIntervalSince1970),
            updatedAt: Int(Date().timeIntervalSince1970)
        )
        try entryRepo.insert(entry)

        // Test conversion
        let monitor = ConversationMonitor.shared
        let timelineEntry = await monitor.convertToTimelineEntry(entry)

        XCTAssertEqual(timelineEntry.kind, .user)
        XCTAssertEqual(timelineEntry.detail, "Hello, world!")
        XCTAssertEqual(timelineEntry.sourceContext?.provider, .claudeCode)
    }

    func testTimelineCacheIntegration() async throws {
        let cacheRepo = TimelineCacheRepositoryImpl(db: db)

        // Save cache entry
        let cache = TimelineCache(
            contentSha256: "sha256:abc123",
            windowSha256: "sha256:def456",
            entryId: "msg-1",
            generatorSignature: "test-sig",
            disposition: "active",
            presentForm: "You are asking a question",
            pastForm: "You asked a question",
            selectedForm: "present",
            verbLemma: "ask",
            generatedAt: Int(Date().timeIntervalSince1970),
            userEdited: 0,
            userText: nil,
            editedAt: nil,
            requestId: nil,
            duration: 0.5
        )
        try cacheRepo.upsert(cache)

        // Retrieve cache
        let retrieved = try cacheRepo.get(
            contentSha256: "sha256:abc123",
            windowSha256: "sha256:def456"
        )

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.presentForm, "You are asking a question")
        XCTAssertEqual(retrieved?.selectedForm, "present")
    }
}
```

### 4.2 Integration Tests (Update Existing)

**File:** `Contextify/ContextifyTests/IntegrationTests.swift`

Add new test:

```swift
func testFullTimelineFlow() async throws {
    // 1. Create project and transcript
    let projectId = try projectRepo.create(name: "Test", rootPath: "/test", bookmark: nil)

    // 2. Mock transcript file
    let transcriptPath = tempDir.appendingPathComponent("test.jsonl")
    let mockTranscript = """
    {"uuid":"msg-1","type":"user","timestamp":"2025-10-11T12:00:00.000Z","sessionId":"s1","message":{"role":"user","content":"Write tests"},gitBranch":"main"}
    {"uuid":"msg-2","type":"assistant","timestamp":"2025-10-11T12:00:01.000Z","sessionId":"s1","message":{"role":"assistant","content":"I'll write tests for you"},gitBranch":"main"}
    """
    try mockTranscript.write(to: transcriptPath, atomically: true, encoding: .utf8)

    // 3. Hoover transcript
    let transcriptId = try transcriptRepo.upsert(projectId: projectId, fileURL: transcriptPath, ...)
    let transcript = try transcriptRepo.get(transcriptId)!
    let progress = NoOpProgressSink()
    _ = try hooverEngine.hooverTranscript(transcript, fileURL: transcriptPath, progress: progress)

    // 4. Load entries into timeline
    let monitor = ConversationMonitor.shared
    await monitor.startMonitoring(projectId: projectId)
    await monitor.loadEntriesFromSQL()

    // 5. Verify timeline populated
    XCTAssertEqual(monitor.visibleEntries.count, 2)
    XCTAssertEqual(monitor.visibleEntries[0].kind, .user)
    XCTAssertEqual(monitor.visibleEntries[1].kind, .assistant)

    // 6. Verify cache was generated
    let cacheRepo = TimelineCacheRepositoryImpl(db: pool)
    let cacheCount = try pool.read { db in
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timeline_cache") ?? 0
    }
    XCTAssertEqual(cacheCount, 2, "Should have cached summaries for both entries")
}
```

### 4.3 Manual Testing Checklist

**Pre-Integration Checklist:**
- [ ] File-based timeline working (baseline)
- [ ] SQL backend passing all tests (`make test`)
- [ ] Fresh `transcripts.db` created at expected path

**Integration Checklist:**
1. **Initial Load**
   - [ ] Launch app with empty database
   - [ ] Verify project created in SQL
   - [ ] Verify initial hoover runs (logs show "Hoovered transcript X")
   - [ ] Verify timeline populates within 5 seconds
   - [ ] Check DB: `SELECT COUNT(*) FROM transcript_entries` > 0

2. **Real-Time Updates**
   - [ ] Open iTerm2, start Claude Code session
   - [ ] Send message: "Hello from iTerm"
   - [ ] Verify new entry appears in timeline within 2 seconds
   - [ ] Check logs: "TranscriptUpdated notification received"
   - [ ] Verify entry stored in SQL: `SELECT * FROM transcript_entries ORDER BY timestamp DESC LIMIT 1`

3. **Timeline Cache**
   - [ ] Reload app (keep same database)
   - [ ] Verify timeline loads faster (cache hits)
   - [ ] Check logs: "Cache HIT from SQL" (not "Cache MISS")
   - [ ] Check DB: `SELECT COUNT(*) FROM timeline_cache` > 0

4. **Transcript Metadata**
   - [ ] Open transcripts
   - [ ] Verify metadata generation triggers for uncached sessions
   - [ ] Check logs: "Generating metadata for {session}"
   - [ ] Verify DB: `SELECT * FROM transcript_metadata` has records
   - [ ] Verify no `.metadata.json` sidecar files on disk

5. **Performance**
   - [ ] Load timeline with 500+ entries (should complete in <1s)
   - [ ] Check memory usage (no spikes from in-memory caches)
   - [ ] Check database size (<50MB for 10K entries)

6. **Error Handling**
   - [ ] Delete `transcripts.db` while app running
   - [ ] Verify graceful error message (not crash)
   - [ ] Restart app, verify DB recreated
   - [ ] Verify timeline repopulates

---

## Part 5: Keyword Sweep (Post-Implementation)

**Objective:** Find and remove all file-based legacy code after SQL integration.

### 5.1 Filesystem I/O Patterns

```bash
# Search for direct file reads of JSONL
rg "String\(contentsOf.*\.jsonl" --type swift

# Search for file watcher setup
rg "DispatchSource\.makeFileSystemObjectSource" --type swift

# Search for cache directory access
rg "TimelineCache.*Application Support" --type swift

# Search for sidecar file operations
rg "\.metadata\.json" --type swift
```

Expected removals:
- `ConversationMonitor.swift`: Remove `processConversationFile()`, file watchers
- `TimelineCacheStore.swift`: Delete entire file
- `TranscriptMetadataStore.swift`: Delete `SidecarMetadataStore` struct
- `TranscriptParser.swift`: Keep for SQL migration only, mark deprecated

### 5.2 Legacy Data Structure References

```bash
# Search for old cache models
rg "CachedTimelineEntry|CacheIndex" --type swift

# Search for old metadata models
rg "TranscriptMetadata.*sidecar" --type swift

# Search for file-based session discovery
rg "contentsOfDirectory.*\.jsonl" --type swift
```

Expected removals:
- `TimelineCache.swift`: Remove `CacheIndex`, `CachedTimelineEntry` (replaced by SQL models)
- `TranscriptMetadata.swift`: Remove sidecar-specific fields

### 5.3 Deprecated Methods

```bash
# Search for methods that should no longer be called
rg "parseExchanges\(url:" --type swift
rg "load\(for.*URL\)" --type swift  # File-based load methods
rg "save\(_.*for.*URL\)" --type swift  # File-based save methods
```

Expected actions:
- Mark methods with `@available(*, deprecated, message: "Use SQL backend")`
- Remove calls from active code paths
- Keep for 1 release cycle for compatibility

### 5.4 Configuration Cleanup

```bash
# Search for file-based paths in config
rg "TimelineCache|Application Support.*Contextify" --type swift

# Search for legacy UserDefaults keys
rg "UserDefaults.*Timeline" --type swift
```

Expected removals:
- Remove `CONTEXTIFY_CACHE_DIR` environment variable support
- Remove legacy preferences for file-based system

---

## Part 6: Performance Validation

### 6.1 Performance Targets (From Original Spec)

| Operation | Target (p95) | Measurement Method |
|-----------|--------------|-------------------|
| Recent feed load (50 entries) | ≤5ms | `os_signpost` around `getRecentEntries()` |
| Timeline cache lookup | ≤5ms | `os_signpost` around `getCachedEntry()` |
| New entry insert (stream) | ≤20ms | `os_signpost` around `hooverTranscript()` with 1 new line |
| Initial hoover (1K entries) | ≤2s | Wall clock time for `discoverTranscripts()` |

### 6.2 Performance Test Script

```swift
// Add to IntegrationTests.swift:
func testTimelinePerformance() throws {
    // Setup: 500 entries in SQL
    let projectId = try setupProjectWith500Entries()

    // Test 1: Recent feed load
    measure {
        _ = try? orchestrator.getRecentEntries(forProject: projectId, limit: 50)
    }
    // Expected: <5ms per iteration

    // Test 2: Cache lookup
    measure {
        _ = try? cacheRepo.get(contentSha256: "sha256:test", windowSha256: "sha256:window")
    }
    // Expected: <5ms per iteration

    // Test 3: Stream insert
    measure {
        let entry = TranscriptEntry(id: UUID().uuidString, ...)
        try? entryRepo.insert(entry)
    }
    // Expected: <20ms per iteration
}
```

### 6.3 Database Optimization Checklist

- [ ] Run `ANALYZE` after initial hoover: `try pool.write { db in try db.execute(sql: "ANALYZE") }`
- [ ] Verify indexes used: `EXPLAIN QUERY PLAN SELECT * FROM transcript_entries WHERE project_id = ?`
- [ ] Check WAL size: `PRAGMA wal_checkpoint(PASSIVE)`
- [ ] Verify foreign keys enforced: `PRAGMA foreign_key_check`

---

## Part 7: Rollout Plan

### Phase 1: Development (Current)
- Implement integration changes (Parts 2.1-2.5)
- Run unit tests (Part 4.1)
- Run integration tests (Part 4.2)
- Manual smoke tests (Part 4.3)

### Phase 2: Internal Alpha
- Enable SQL backend by default
- Keep file-based fallback flag
- Monitor logs for errors
- Collect performance metrics
- 1-2 weeks of dogfooding

### Phase 3: Beta Release
- Remove fallback flag (SQL-only)
- Delete legacy file-based code (Part 5)
- Update documentation
- Public beta for 2-4 weeks

### Phase 4: Production
- Stable release with SQL backend
- Monitor crash reports (Sentry/Crashlytics)
- Performance dashboard
- Migration guide for users

---

## Part 8: Implementation Checklist

### Code Changes
- [ ] 2.1.A: Replace file reading with SQL queries in `ConversationMonitor`
- [ ] 2.1.B: Add `convertToTimelineEntry()` helper
- [ ] 2.1.C: Replace file watchers with SQL notifications
- [ ] 2.2.A: Replace `TimelineCacheStore` with `TimelineCacheRepository` in orchestrator
- [ ] 2.2.B: Update cache lookup to use SQL
- [ ] 2.2.C: Update cache save to use SQL
- [ ] 2.3.A: Replace `SidecarMetadataStore` with `MetadataRepository`
- [ ] 2.3.B: Load metadata from SQL
- [ ] 2.3.C: Generate metadata from SQL entries
- [ ] 2.4.A: Discover sessions from SQL
- [ ] 2.4.B: Add initial hoover for new projects
- [ ] 2.5.A: Initialize SQL backend on startup

### Testing
- [ ] 4.1: Add `TimelineIntegrationTests.swift` with unit tests
- [ ] 4.2: Add `testFullTimelineFlow()` to `IntegrationTests.swift`
- [ ] 4.3: Run manual testing checklist (all items)

### Cleanup
- [ ] 5.1: Run keyword sweep for filesystem I/O
- [ ] 5.2: Run keyword sweep for legacy data structures
- [ ] 5.3: Mark deprecated methods
- [ ] 5.4: Remove legacy configuration

### Validation
- [ ] 6.1: Run performance tests, verify targets met
- [ ] 6.2: Run `testTimelinePerformance()`
- [ ] 6.3: Database optimization checklist complete

### Documentation
- [ ] Update `README.md` with SQL backend usage
- [ ] Update `CLAUDE.md` with new architecture
- [ ] Add migration notes for users

---

## Appendix A: SQL Queries Reference

### Timeline Queries

```sql
-- Get recent entries for timeline (sorted by timestamp DESC)
SELECT * FROM transcript_entries
WHERE project_id = ? AND display_in_timeline = 1
ORDER BY timestamp DESC
LIMIT 50;

-- Get entries for specific transcript
SELECT * FROM transcript_entries
WHERE transcript_id = ?
ORDER BY timestamp ASC;

-- Get new entries since last check
SELECT * FROM transcript_entries
WHERE project_id = ? AND timestamp > ?
ORDER BY timestamp ASC;
```

### Cache Queries

```sql
-- Check cache (composite PK lookup)
SELECT * FROM timeline_cache
WHERE content_sha256 = ? AND window_sha256 = ?;

-- Insert/update cache (upsert)
INSERT INTO timeline_cache (
    content_sha256, window_sha256, entry_id, generator_signature,
    disposition, present_form, past_form, selected_form,
    verb_lemma, generated_at, user_edited, user_text, edited_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (content_sha256, window_sha256) DO UPDATE SET
    entry_id = excluded.entry_id,
    present_form = excluded.present_form,
    past_form = excluded.past_form,
    updated_at = CURRENT_TIMESTAMP;

-- Cache statistics
SELECT
    (SELECT COUNT(*) FROM timeline_cache) as cached_entries,
    (SELECT COUNT(*) FROM transcript_entries) as total_entries,
    ROUND(100.0 * (SELECT COUNT(*) FROM timeline_cache) / (SELECT COUNT(*) FROM transcript_entries), 2) as cache_hit_rate;
```

### Metadata Queries

```sql
-- Get metadata for transcript
SELECT * FROM transcript_metadata
WHERE transcript_id = ?;

-- Find stale metadata (needs regeneration)
SELECT transcript_id FROM transcript_metadata
WHERE prompt_version < ? OR generator_version < ?;

-- Insert/update metadata
INSERT INTO transcript_metadata (
    transcript_id, project_id, title, description, topics,
    confidence, generated_at, model, prompt_version,
    generator_version, transcript_sha256, message_count,
    strategy, llm_calls, latency_ms, created_at, updated_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT (transcript_id) DO UPDATE SET
    title = excluded.title,
    description = excluded.description,
    topics = excluded.topics,
    updated_at = excluded.updated_at;
```

---

## Appendix B: Error Handling Patterns

### SQL Errors

```swift
// Pattern: Try SQL first, fall back to graceful degradation
func loadEntries() async throws {
    do {
        let entries = try await orchestrator.getRecentEntries(forProject: projectId, limit: 50)
        self.visibleEntries = entries.map { await convertToTimelineEntry($0) }
    } catch let error as DatabaseError {
        log.error("SQL query failed: \(error.message, privacy: .public)")
        // Show user-facing error
        self.lastError = "Database error. Please restart the app."
    } catch {
        log.error("Unexpected error loading entries: \(error.localizedDescription, privacy: .public)")
        self.lastError = "Failed to load timeline. Please check logs."
    }
}
```

### LLM Generation Errors

```swift
// Pattern: Use heuristic fallback for cache misses when LLM fails
func generateSummary(for entry: TranscriptEntry) async throws -> String {
    do {
        let llmResult = try await FoundationLLM.shared.summarizeTimelineWithForms(...)
        return llmResult.presentForm
    } catch {
        log.warning("LLM generation failed for entry \(entry.id), using heuristic fallback")
        // Simple heuristic: truncate content to 100 chars
        return String(entry.content.prefix(100))
    }
}
```

### Database Corruption

```swift
// Pattern: Detect corruption, offer rebuild option
func validateDatabase() async throws {
    do {
        try pool.read { db in
            try db.execute(sql: "PRAGMA quick_check")
        }
    } catch {
        log.fault("Database corrupted: \(error.localizedDescription)")

        // Offer user rebuild option
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Database Corrupted"
            alert.informativeText = "The timeline database is corrupted. Would you like to rebuild it?"
            alert.addButton(withTitle: "Rebuild")
            alert.addButton(withTitle: "Quit")

            if alert.runModal() == .alertFirstButtonReturn {
                Task {
                    try await rebuildDatabase()
                }
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

func rebuildDatabase() async throws {
    // Delete corrupted database
    let dbPath = try DatabaseManager.shared.databasePath()
    try FileManager.default.removeItem(at: dbPath)

    // Recreate and re-hoover
    let pool = try DatabaseManager.shared.pool
    try pool.write { db in try DatabaseSchema.migrate(db) }

    // Re-discover all transcripts
    try await ConversationSources.shared.discoverAndHooverNewTranscripts(projectId: projectId)
}
```

---

## Appendix C: Logging Standards

### Integration Points

```swift
// Use .info for integration milestones
log.info("Starting SQL backend initialization")
log.info("Loaded \(entries.count) entries from SQL")
log.info("Timeline cache hit rate: \(hitRate)%")

// Use .debug for routine operations (hidden in production)
log.debug("Querying recent entries for project \(projectId, privacy: .public)")
log.debug("Converting SQL entry \(entry.id, privacy: .public) to TimelineEntry")

// Use .warning for degraded performance
log.warning("LLM generation took \(duration)ms (>500ms threshold)")
log.warning("Cache miss rate high: \(missRate)% (target: <20%)")

// Use .error for failures requiring user action
log.error("Failed to load entries from SQL: \(error.localizedDescription, privacy: .public)")
log.error("Database migration failed, cannot start app")
```

---

## End of Document

**Next Steps:**
1. Review this plan with stakeholders
2. Create feature branch: `feature/sql-timeline-integration`
3. Implement Part 2 (Component Integration) in atomic commits
4. Run testing checklist (Part 4)
5. Perform keyword sweep (Part 5)
6. Validate performance (Part 6)
7. Merge to `main` after approval

**Estimated Implementation Time:** 8-12 hours
**Testing Time:** 4-6 hours
**Total:** 12-18 hours (1.5-2 engineering days)
