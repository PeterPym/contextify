# Technical Brief: SQL-Based Local Storage Architecture for Contextify

**Author:** Claude (Architectural Analysis)
**Date:** 2025-10-10
**Status:** Architectural Study
**Scope:** Complete replacement of file-based storage with SQL database

---

## Executive Summary

This brief provides a comprehensive architectural analysis for migrating Contextify from its current JSON file-based storage to a SQL database solution. The migration addresses scalability, performance, and query complexity limitations while maintaining the app's robust concurrency model and macOS-native design principles.

**Key Recommendations:**
- **Primary Choice:** GRDB.swift with SQLite backend
- **Schema Design:** Normalized relational model with indexed lookups
- **Migration Strategy:** Phased rollout with backward compatibility
- **Timeline:** 3-4 week implementation in 4 phases

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [SQL Technology Evaluation](#sql-technology-evaluation)
3. [Recommended Architecture](#recommended-architecture)
4. [Schema Design](#schema-design)
5. [Migration Strategy](#migration-strategy)
6. [Best Practices for macOS](#best-practices-for-macos)
7. [Performance Considerations](#performance-considerations)
8. [Concurrency & Swift 6](#concurrency--swift-6)
9. [Implementation Roadmap](#implementation-roadmap)
10. [Risk Assessment](#risk-assessment)

---

## 1. Current State Analysis

### 1.1 Existing Storage Components

#### **TimelineCacheStore** (`TimelineCacheStore.swift`)
- **Format:** JSON files with SHA256 checksums
- **Location:** `~/Library/Application Support/Contextify/TimelineCache/`
- **Structure:** Hash-based directory hierarchy
- **Features:**
  - Atomic writes with temp files + `fsync`
  - Content integrity via SHA256 checksums
  - Corruption quarantine system
  - Per-conversation cache files

**Data Model:**
```swift
struct TimelineCache {
    var schemaVersion: String
    var conversationPath: String
    var entries: [String: CachedTimelineEntry]  // UUID → Entry
    var metadata: CacheMetadata
}

struct CachedTimelineEntry {
    let contentHash: String
    let windowHash: String
    let generatorSignature: String
    let disposition: Disposition
    let presentForm: String
    let pastForm: String
    var selectedForm: Tense
    // ... more fields
}
```

#### **SidecarMetadataStore** (`TranscriptMetadataStore.swift`)
- **Format:** JSON sidecar files
- **Location:** Adjacent to transcript files (`.metadata.json`)
- **Purpose:** LLM-generated transcript summaries
- **Features:**
  - Streaming SHA256 hash (64KB chunks)
  - Freshness validation via hash + version
  - Atomic writes

**Data Model:**
```swift
struct TranscriptMetadata {
    var title: String
    var description: String
    var topics: [String]
    var confidence: Double
    var generatedAt: Date
    var transcriptSHA256: String
    // ... metrics
}
```

#### **HUDPreferences** (`HUDCore.swift`)
- **Format:** UserDefaults (plist)
- **Purpose:** App preferences
- **Features:**
  - Suite-based defaults (`dev.contextify`)
  - Security-scoped bookmarks for sandboxing
  - Fallback to standard defaults

**Data:**
```swift
- projectRootKey: String path
- projectRootBookmarkKey: Data (security-scoped)
- autoPersistKey: Bool
```

### 1.2 Pain Points with Current Approach

#### **Performance Issues**
1. **Linear scans**: No indexing on common queries (by timestamp, provider, session)
2. **Full file reads**: Must deserialize entire JSON to query single entry
3. **No pagination**: Cannot efficiently load recent N entries
4. **Fragmentation**: Each conversation = separate file (harder to query across conversations)

#### **Scalability Limitations**
1. **Memory footprint**: All entries loaded into memory for modifications
2. **File I/O overhead**: Atomic writes require full serialization per update
3. **Concurrent access**: File locking limits parallel operations
4. **Storage bloat**: JSON overhead ~30-40% vs binary formats

#### **Query Complexity**
1. **Cross-conversation queries**: Requires reading all cache files
2. **Temporal queries**: No efficient "last 24 hours" without scanning
3. **Aggregations**: Cannot compute statistics without loading everything
4. **Search**: Full-text search requires custom indexing

#### **Integrity Challenges**
1. **Partial failures**: Checksum mismatch = lose entire cache
2. **Race conditions**: Multiple processes could corrupt cache
3. **Backup complexity**: Must coordinate file copies with checksums

---

## 2. SQL Technology Evaluation

### 2.1 Comparison Matrix

| Technology | Type | Pros | Cons | Verdict |
|------------|------|------|------|---------|
| **SQLite (raw)** | Embedded DB | Ubiquitous, battle-tested, zero config | Manual Swift bindings, unsafe APIs, complex threading | ❌ Too low-level |
| **GRDB.swift** | SQLite wrapper | Type-safe, excellent Swift integration, migration tools, observability | Learning curve, dependency | ✅ **RECOMMENDED** |
| **SwiftData** | Apple ORM | Native, SwiftUI integration, compile-time safety | macOS 14+ only, limited control, young API | ⚠️ Too restrictive |
| **Core Data** | Apple ORM | Mature, powerful, iCloud sync | Heavy, XML schemas, complex debugging, outdated patterns | ❌ Overkill |
| **Realm** | Mobile DB | Fast, reactive, great for mobile | Large binary, acquisition uncertainty (MongoDB), overkill | ❌ Not native |

### 2.2 Detailed Analysis

#### **GRDB.swift** ✅ RECOMMENDED

**Strengths:**
- **Type Safety**: Compile-time checked SQL with Swift types
- **Concurrency Model**: Built-in support for Swift concurrency (async/await)
- **Migrations**: Version-controlled schema migrations with rollback
- **Observation**: Reactive queries with Combine/AsyncSequence integration
- **Performance**: Zero-copy reads, prepared statement pooling
- **macOS Native**: Leverages macOS SQLite optimizations
- **Maintainability**: Well-documented, active development, pure Swift

**Code Example:**
```swift
// Define model
struct CachedEntry: Codable, FetchableRecord, PersistableRecord {
    var uuid: String
    var contentHash: String
    var summary: String
    var timestamp: Date
}

// Type-safe query
let recent = try dbQueue.read { db in
    try CachedEntry
        .filter(Column("timestamp") > Date().addingTimeInterval(-86400))
        .order(Column("timestamp").desc)
        .limit(50)
        .fetchAll(db)
}
```

**Why GRDB over alternatives:**
1. **SwiftData** - Too new, limited to macOS 14+, less control
2. **Core Data** - Heavy XML schemas, complex for simple KV needs
3. **Raw SQLite** - Unsafe C APIs, manual threading, error-prone

#### **SwiftData** ⚠️ CONSIDER FOR FUTURE

**Evaluation:**
- **Pros**: Native, automatic SwiftUI integration, modern Swift syntax
- **Cons**:
  - Requires macOS 14+ (current min deployment: macOS 14/15)
  - Less mature (introduced WWDC 2023)
  - Limited query flexibility compared to raw SQL
  - Opaque persistence layer

**Recommendation**: Monitor for future adoption when minimum OS is macOS 15+

#### **Core Data** ❌ NOT RECOMMENDED

**Reasons for rejection:**
1. XML schema files (`.xcdatamodel`) add build complexity
2. NSManagedObject concurrency rules conflict with Swift 6 strict concurrency
3. Heavyweight for simple caching use case
4. Debugging is notoriously difficult (opaque errors)
5. iCloud sync not needed for local-only app

---

## 3. Recommended Architecture

### 3.1 High-Level Design

```
┌─────────────────────────────────────────────────────┐
│                  Application Layer                   │
│         (ViewModels, Orchestrators, Monitors)        │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│              Repository Layer (Actor)                │
│  ┌──────────────────┐  ┌──────────────────────────┐ │
│  │ TimelineRepo     │  │ TranscriptMetadataRepo   │ │
│  │ (GRDB interface) │  │ (GRDB interface)         │ │
│  └──────────────────┘  └──────────────────────────┘ │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                  GRDB Database Layer                 │
│  ┌──────────────────────────────────────────────┐   │
│  │  DatabaseQueue (write) / DatabasePool (read) │   │
│  │  - Schema migrations                         │   │
│  │  - Transaction management                    │   │
│  │  - Connection pooling                        │   │
│  └──────────────────────────────────────────────┘   │
└────────────────────────┬────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────┐
│                SQLite Database File                  │
│  ~/Library/Application Support/Contextify/cache.db  │
└─────────────────────────────────────────────────────┘
```

### 3.2 Repository Pattern with Swift Actors

**Rationale:**
- Encapsulate database logic behind async interfaces
- Leverage Swift 6 actors for thread-safe access
- Support observable patterns for UI updates

**Example Repository:**
```swift
@globalActor actor DatabaseActor {
    static let shared = DatabaseActor()
}

@DatabaseActor
final class TimelineRepository {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    // Write operations
    func save(_ entry: CachedTimelineEntry) async throws {
        try await dbQueue.write { db in
            try entry.save(db)
        }
    }

    // Read operations (can use DatabasePool for parallelism)
    func fetchRecent(limit: Int) async throws -> [CachedTimelineEntry] {
        try await dbQueue.read { db in
            try CachedTimelineEntry
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // Observable queries for UI
    func observeRecent(limit: Int) -> AsyncThrowingStream<[CachedTimelineEntry], Error> {
        ValueObservation
            .tracking { db in
                try CachedTimelineEntry
                    .order(Column("timestamp").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
            .values(in: dbQueue)
    }
}
```

### 3.3 Database Location Strategy

**Primary Location:** `~/Library/Application Support/Contextify/`

```
Contextify/
├── cache.db                    # Main SQLite database
├── cache.db-wal               # Write-ahead log (WAL mode)
├── cache.db-shm               # Shared memory file
├── backups/                   # Automated backups
│   ├── cache-2025-10-10.db
│   └── cache-2025-10-09.db
└── migrations/                # Schema version tracking
    └── applied.json
```

**Sandboxing Considerations:**
- Use security-scoped bookmarks for user-selected directories
- Default to Application Support (always accessible)
- WAL mode for better concurrent access

---

## 4. Schema Design

### 4.1 Core Tables

#### **conversations**
Tracks conversation sessions (replaces per-file storage)

```sql
CREATE TABLE conversations (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL UNIQUE,
    provider TEXT NOT NULL,  -- claudeCode, codexCLI, other
    project_root TEXT,
    last_activity DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_path)
);

CREATE INDEX idx_conversations_last_activity ON conversations(last_activity DESC);
CREATE INDEX idx_conversations_provider ON conversations(provider);
```

#### **timeline_entries**
Main cache table (replaces TimelineCache entries dict)

```sql
CREATE TABLE timeline_entries (
    uuid TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,

    -- Content validation
    content_hash TEXT NOT NULL,
    window_hash TEXT NOT NULL,
    generator_signature TEXT NOT NULL,

    -- Core data
    disposition TEXT NOT NULL,  -- Disposition enum
    present_form TEXT NOT NULL,
    past_form TEXT NOT NULL,
    selected_tense TEXT NOT NULL DEFAULT 'present',  -- Tense enum

    -- Metadata
    timestamp DATETIME NOT NULL,
    generated_at DATETIME NOT NULL,

    -- Optional fields
    verb_lemma TEXT,
    request_id TEXT,
    duration_seconds REAL,

    -- User overrides
    user_edited INTEGER DEFAULT 0,
    user_text TEXT,
    edited_at DATETIME,

    -- Session tracking
    session_id TEXT,

    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_timeline_timestamp ON timeline_entries(conversation_id, timestamp DESC);
CREATE INDEX idx_timeline_session ON timeline_entries(session_id, timestamp DESC);
CREATE INDEX idx_timeline_disposition ON timeline_entries(disposition);
CREATE INDEX idx_timeline_content_hash ON timeline_entries(content_hash);
```

#### **transcript_metadata**
Replaces JSON sidecar files

```sql
CREATE TABLE transcript_metadata (
    file_path TEXT PRIMARY KEY,

    -- Core metadata
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    topics TEXT NOT NULL,  -- JSON array
    confidence REAL NOT NULL,
    may_contain_hallucinations INTEGER NOT NULL,
    needs_review INTEGER NOT NULL,

    -- Generation info
    generated_at DATETIME NOT NULL,
    model TEXT NOT NULL,
    prompt_version INTEGER NOT NULL,
    generator_version INTEGER NOT NULL,

    -- Validation
    transcript_sha256 TEXT NOT NULL,
    message_count INTEGER NOT NULL,
    strategy TEXT NOT NULL,
    llm_calls INTEGER NOT NULL,
    latency_ms INTEGER NOT NULL,

    -- Timestamps
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_metadata_needs_review ON transcript_metadata(needs_review);
CREATE INDEX idx_metadata_confidence ON transcript_metadata(confidence);
CREATE INDEX idx_metadata_updated_at ON transcript_metadata(updated_at DESC);
```

#### **cache_metadata**
Per-conversation statistics (replaces CacheMetadata struct)

```sql
CREATE TABLE cache_metadata (
    conversation_id TEXT PRIMARY KEY,
    total_entries INTEGER NOT NULL DEFAULT 0,
    last_flush DATETIME,
    cache_hits INTEGER NOT NULL DEFAULT 0,
    cache_misses INTEGER NOT NULL DEFAULT 0,
    regenerations INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);
```

#### **app_preferences**
Replaces UserDefaults (optional - could keep UserDefaults for simplicity)

```sql
CREATE TABLE app_preferences (
    key TEXT PRIMARY KEY,
    value TEXT,
    value_type TEXT NOT NULL,  -- string, bool, int, data
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Reserved for critical preferences; UserDefaults still viable for simple KV
```

### 4.2 Schema Versioning

**Migration Strategy with GRDB:**

```swift
var migrator = DatabaseMigrator()

// v1: Initial schema
migrator.registerMigration("v1_initial") { db in
    try db.create(table: "conversations") { t in
        t.column("id", .text).primaryKey()
        t.column("file_path", .text).notNull().unique()
        t.column("provider", .text).notNull()
        t.column("last_activity", .datetime).notNull()
        t.column("created_at", .datetime).notNull()
    }

    try db.create(table: "timeline_entries") { t in
        t.column("uuid", .text).primaryKey()
        t.column("conversation_id", .text).notNull()
            .references("conversations", onDelete: .cascade)
        // ... all columns
    }

    // Create indexes
    try db.create(index: "idx_timeline_timestamp",
                  on: "timeline_entries",
                  columns: ["conversation_id", "timestamp"])
}

// v2: Add session_id to timeline_entries (example future migration)
migrator.registerMigration("v2_session_tracking") { db in
    try db.alter(table: "timeline_entries") { t in
        t.add(column: "session_id", .text)
    }
    try db.create(index: "idx_timeline_session",
                  on: "timeline_entries",
                  columns: ["session_id", "timestamp"])
}

// v3: Add full-text search (example)
migrator.registerMigration("v3_full_text_search") { db in
    try db.create(virtualTable: "timeline_fts", using: .FTS5()) { t in
        t.synchronize(withTable: "timeline_entries")
        t.column("present_form")
        t.column("past_form")
    }
}
```

---

## 5. Migration Strategy

### 5.1 Phased Rollout (4 Phases)

#### **Phase 1: Parallel Write (Week 1)**
- Install GRDB dependency via SPM
- Implement repository layer alongside existing stores
- Write to both JSON files AND SQL database
- Read from JSON (existing behavior)
- **Goal:** Validate SQL schema without breaking anything

```swift
// Example: Dual-write pattern
actor TimelineCacheOrchestrator {
    private let legacyStore = TimelineCacheStore()
    private let sqlRepo = TimelineRepository()  // NEW

    func save(_ cache: TimelineCache, for url: URL) async throws {
        // Write to both stores
        try await legacyStore.save(cache, for: url)
        try await sqlRepo.saveConversation(cache, url: url)  // NEW
    }
}
```

#### **Phase 2: Incremental Migration (Week 2)**
- Background task to migrate existing JSON → SQL
- Progress tracking & resumable migration
- Keep JSON as fallback
- **Goal:** Migrate historical data without blocking app

```swift
@MainActor
func migrateHistoricalData() async {
    let files = try FileManager.default.contentsOfDirectory(at: cacheDir)

    for file in files where file.pathExtension == "json" {
        // Load legacy format
        let cache = try await legacyStore.load(for: file)

        // Write to SQL
        try await sqlRepo.saveConversation(cache, url: file.conversationURL)

        // Update progress
        progress += 1
    }
}
```

#### **Phase 3: Read from SQL (Week 3)**
- Switch read path to SQL
- Fall back to JSON if SQL fails
- A/B test performance
- **Goal:** Validate SQL performance in production

```swift
func load(for url: URL) async throws -> TimelineCache? {
    // Try SQL first
    if let sqlCache = try? await sqlRepo.loadConversation(url: url) {
        return sqlCache
    }

    // Fallback to legacy
    return try await legacyStore.load(for: url)
}
```

#### **Phase 4: Deprecate JSON (Week 4)**
- Remove legacy JSON writes
- Keep JSON read for emergency rollback
- Archive old files after N days
- **Goal:** Complete migration, reduce code complexity

### 5.2 Rollback Plan

**If critical issues arise:**

1. **Immediate:** Flip feature flag to revert to JSON reads
2. **Short-term:** Disable SQL writes, continue JSON dual-write
3. **Long-term:** Fix issues, re-enable phased rollout

**Feature Flag Implementation:**
```swift
enum StorageBackend {
    case json
    case sql
    case hybrid  // Dual-write
}

actor FeatureFlags {
    static var storageBackend: StorageBackend = .hybrid
}
```

---

## 6. Best Practices for macOS

### 6.1 File System Considerations

#### **WAL Mode (Write-Ahead Logging)**
- **Enable:** Better concurrency, atomic commits
- **Tradeoff:** Extra files (`.db-wal`, `.db-shm`), but worth it

```swift
let dbQueue = try DatabaseQueue(path: dbPath)
try dbQueue.write { db in
    try db.execute(sql: "PRAGMA journal_mode = WAL")
    try db.execute(sql: "PRAGMA synchronous = NORMAL")  // Balance speed/safety
}
```

#### **Sandboxing Support**
- Store DB in `~/Library/Application Support/Contextify/`
- Request read/write access if user changes location
- Use security-scoped bookmarks for persistent access

```swift
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let dbPath = appSupport.appendingPathComponent("Contextify/cache.db").path
```

#### **Backup Strategy**
- Automated daily backups before app quit
- Keep last 7 days of backups
- Use `VACUUM INTO` for compact backups

```swift
func backupDatabase() async throws {
    let backupPath = backupDir.appendingPathComponent("cache-\(today).db").path
    try await dbQueue.backup(to: DatabaseQueue(path: backupPath))
}
```

### 6.2 Performance Optimization

#### **Prepared Statements**
- GRDB automatically pools prepared statements
- Reuse queries for repeated operations

```swift
// GRDB handles this internally
let recentEntries = try dbQueue.read { db in
    try CachedEntry
        .filter(Column("timestamp") > cutoff)
        .fetchAll(db)  // Statement is prepared & cached
}
```

#### **Batch Operations**
- Use transactions for bulk inserts/updates
- Reduces fsync calls from N to 1

```swift
try await dbQueue.write { db in
    for entry in entries {
        try entry.insert(db)  // All in one transaction
    }
}
```

#### **Indexes**
- Index all foreign keys
- Composite indexes for common query patterns
- Monitor with `EXPLAIN QUERY PLAN`

```sql
-- Good: Covers common pattern (conversation + time range)
CREATE INDEX idx_timeline_conv_time ON timeline_entries(
    conversation_id,
    timestamp DESC
);

-- Bad: Redundant with above
CREATE INDEX idx_timeline_conv ON timeline_entries(conversation_id);
```

### 6.3 Memory Management

#### **Lazy Loading**
- Don't load all entries at once
- Use cursors for large result sets

```swift
// Bad: Loads everything into memory
let all = try timeline_entries.fetchAll(db)

// Good: Stream results
let cursor = try timeline_entries.fetchCursor(db)
while let entry = try cursor.next() {
    process(entry)
}
```

#### **Page Size Tuning**
- macOS default: 4KB pages
- Consider 8KB for better sequential read performance

```swift
try db.execute(sql: "PRAGMA page_size = 8192")
try db.vacuum()  // Rebuild with new page size
```

---

## 7. Concurrency & Swift 6

### 7.1 Actor Isolation

**Current Pattern (JSON):**
```swift
actor TimelineCacheOrchestrator {
    private var cache: TimelineCache?  // Actor-isolated

    func save() async throws {
        // Safe: actor serializes access
    }
}
```

**GRDB Pattern (Recommended):**
```swift
@DatabaseActor
final class TimelineRepository {
    private let dbQueue: DatabaseQueue

    func save(_ entry: Entry) async throws {
        // GRDB handles concurrency internally
        try await dbQueue.write { db in
            try entry.insert(db)
        }
    }
}
```

**Why this works:**
- `DatabaseQueue` is thread-safe (uses serial dispatch queue)
- GRDB's async methods bridge to Swift concurrency
- Actor ensures repository-level serialization

### 7.2 Observable Patterns

**SwiftUI Integration:**
```swift
@Observable
@MainActor
class TimelineViewModel {
    private let repo: TimelineRepository
    var entries: [CachedEntry] = []

    func observeTimeline() {
        Task {
            for try await newEntries in repo.observeRecent(limit: 50) {
                self.entries = newEntries
            }
        }
    }
}
```

**GRDB ValueObservation:**
- Automatically re-runs queries when data changes
- Debounces rapid updates
- Delivers on specified queue/actor

### 7.3 Sendable Conformance

**All data models must be Sendable:**
```swift
struct CachedEntry: Codable, Sendable, FetchableRecord {
    let uuid: String
    let summary: String
    // All fields are value types or Sendable
}
```

**GRDB types are Sendable-compatible:**
- `DatabaseQueue` conforms to `Sendable`
- All records crossing actor boundaries must be `Sendable`

---

## 8. Implementation Roadmap

### 8.1 Timeline (4 Weeks)

#### **Week 1: Foundation**
- [ ] Add GRDB dependency via SPM
- [ ] Create repository layer (`TimelineRepository`, `MetadataRepository`)
- [ ] Implement schema migrations
- [ ] Write unit tests for repositories
- [ ] Enable dual-write (JSON + SQL)

**Deliverables:**
- `DatabaseMigrator.swift` - Schema migrations
- `TimelineRepository.swift` - Actor-isolated repository
- `Repositories+Models.swift` - GRDB record types
- Tests: `RepositoryTests.swift`

#### **Week 2: Migration**
- [ ] Build background migration task
- [ ] Add migration UI (progress indicator)
- [ ] Implement resumable migration (crash-safe)
- [ ] Create data validation checks
- [ ] Test with large datasets (10K+ entries)

**Deliverables:**
- `MigrationCoordinator.swift` - Orchestrates JSON → SQL
- `MigrationProgressView.swift` - UI feedback
- Migration logs for debugging

#### **Week 3: Validation**
- [ ] Switch read path to SQL (with JSON fallback)
- [ ] A/B test performance (measure latency)
- [ ] Monitor crash reports
- [ ] Optimize slow queries (EXPLAIN QUERY PLAN)
- [ ] Add telemetry for migration success rate

**Metrics to Track:**
- Query latency (p50, p95, p99)
- Memory usage (before/after)
- Migration success rate
- Crash-free sessions

#### **Week 4: Cleanup**
- [ ] Remove legacy JSON write code
- [ ] Archive old JSON files (optional, keep for emergency)
- [ ] Update documentation
- [ ] Performance audit & final optimizations
- [ ] Ship to production 🚀

**Final Checklist:**
- [ ] All tests passing (unit + integration)
- [ ] Migration success rate > 99.5%
- [ ] No performance regressions
- [ ] Rollback plan tested & documented

### 8.2 Team Responsibilities

**If Multi-Person Team:**
- **Backend Engineer:** Repository layer, migrations
- **iOS Engineer:** SwiftUI integration, observable patterns
- **QA Engineer:** Migration testing, performance validation
- **DevOps:** Monitoring, rollback automation

**Solo Developer (Current):**
- Focus on one phase per week
- Automated testing is critical
- Use feature flags for safe rollout

---

## 9. Risk Assessment

### 9.1 Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Data Loss During Migration** | Low | Critical | - Dual-write during transition<br>- Keep JSON as backup<br>- Automated backups before migration |
| **Performance Regression** | Medium | High | - Benchmark existing performance<br>- Index optimization<br>- Rollback plan ready |
| **Concurrency Bugs** | Medium | Medium | - Extensive unit tests<br>- Actor isolation<br>- GRDB's proven concurrency model |
| **Schema Evolution Issues** | Low | Medium | - Version-controlled migrations<br>- Rollback migrations<br>- Test migration paths |
| **Sandbox Permission Issues** | Low | High | - Use Application Support directory<br>- Test in sandboxed environment<br>- Security-scoped bookmarks |

### 9.2 User Impact

**Positive:**
- ✅ Faster queries (especially for large datasets)
- ✅ Better memory efficiency
- ✅ Cross-conversation analytics possible
- ✅ Full-text search capability

**Negative:**
- ⚠️ One-time migration delay (30-60s for 10K entries)
- ⚠️ Increased disk usage during dual-write phase (+10-20%)
- ⚠️ Learning curve for developers

**Mitigation:**
- Show progress UI during migration
- Clearly communicate benefits in release notes
- Provide documentation & code examples

---

## 10. Conclusion & Recommendations

### 10.1 Final Recommendation

**Proceed with GRDB.swift migration using phased rollout strategy.**

**Rationale:**
1. **Proven Technology**: GRDB is battle-tested in production apps
2. **Swift-Native**: Excellent type safety and concurrency support
3. **Gradual Migration**: Dual-write strategy minimizes risk
4. **Future-Proof**: Scales to millions of entries, supports FTS5, etc.

### 10.2 Success Criteria

**Phase 1 (Foundation):**
- ✅ GRDB integration complete
- ✅ Dual-write working without errors
- ✅ Unit test coverage > 80%

**Phase 2 (Migration):**
- ✅ Historical data migrated successfully
- ✅ Migration resumable after crashes
- ✅ Data integrity verified (checksums match)

**Phase 3 (Validation):**
- ✅ SQL read path performance ≥ JSON read path
- ✅ No increase in crash rate
- ✅ User feedback positive

**Phase 4 (Cleanup):**
- ✅ Legacy code removed
- ✅ Disk usage optimized
- ✅ Documentation updated

### 10.3 Next Steps

1. **Immediate:**
   - Add GRDB to `Package.swift`
   - Create `DatabaseMigrator.swift` skeleton

2. **Short-Term (Week 1):**
   - Implement repository layer
   - Enable dual-write

3. **Long-Term (Weeks 2-4):**
   - Execute migration plan
   - Monitor & optimize

**Estimated Effort:** 80-100 hours (4 weeks @ 20-25 hours/week for solo dev)

---

## Appendix A: Code Examples

### A.1 GRDB Package Dependency

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
],
targets: [
    .target(
        name: "Contextify",
        dependencies: [
            .product(name: "GRDB", package: "GRDB.swift")
        ]
    )
]
```

### A.2 Complete Repository Example

```swift
import GRDB
import Foundation

@globalActor actor DatabaseActor {
    static let shared = DatabaseActor()
}

@DatabaseActor
final class TimelineRepository {
    private let dbQueue: DatabaseQueue

    init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try setupMigrations()
    }

    private func setupMigrations() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "timeline_entries") { t in
                t.column("uuid", .text).primaryKey()
                t.column("conversation_id", .text).notNull()
                t.column("content_hash", .text).notNull()
                t.column("present_form", .text).notNull()
                t.column("past_form", .text).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("disposition", .text).notNull()
            }

            try db.create(index: "idx_timeline_timestamp",
                          on: "timeline_entries",
                          columns: ["conversation_id", "timestamp"])
        }

        try migrator.migrate(dbQueue)
    }

    // CRUD operations
    func save(_ entry: TimelineEntry) async throws {
        try await dbQueue.write { db in
            try entry.insert(db)
        }
    }

    func fetchRecent(conversationId: String, limit: Int) async throws -> [TimelineEntry] {
        try await dbQueue.read { db in
            try TimelineEntry
                .filter(Column("conversation_id") == conversationId)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func observeConversation(id: String) -> AsyncThrowingStream<[TimelineEntry], Error> {
        ValueObservation
            .tracking { db in
                try TimelineEntry
                    .filter(Column("conversation_id") == id)
                    .order(Column("timestamp").desc)
                    .fetchAll(db)
            }
            .values(in: dbQueue)
    }
}

// Model conforming to GRDB protocols
struct TimelineEntry: Codable, Sendable {
    var uuid: String
    var conversationId: String
    var contentHash: String
    var presentForm: String
    var pastForm: String
    var timestamp: Date
    var disposition: String
}

extension TimelineEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "timeline_entries"
}
```

### A.3 Migration Coordinator

```swift
@MainActor
final class MigrationCoordinator: ObservableObject {
    @Published var progress: Double = 0
    @Published var status: String = "Ready"
    @Published var isComplete: Bool = false

    private let legacyStore = TimelineCacheStore()
    private let sqlRepo: TimelineRepository

    func migrateAll() async throws {
        let cacheDir = legacyStore.cacheDirectory
        let files = try FileManager.default.contentsOfDirectory(at: cacheDir,
                                                                 includingPropertiesForKeys: nil)
                                                                 .filter { $0.pathExtension == "json" }

        let total = Double(files.count)
        var completed = 0.0

        for file in files {
            status = "Migrating \(file.lastPathComponent)..."

            // Load legacy format
            guard let cache = try? await legacyStore.load(for: file) else {
                continue
            }

            // Convert to SQL
            try await sqlRepo.saveConversation(cache)

            // Update progress
            completed += 1
            progress = completed / total
        }

        status = "Migration complete!"
        isComplete = true
    }
}
```

---

## Appendix B: Performance Benchmarks

### B.1 Expected Performance Gains

**Query Latency (50 entries):**
- JSON (current): ~15ms (full file read + deserialize)
- SQL (indexed): ~2ms (index seek + fetch)
- **Improvement: 7.5x faster**

**Memory Usage (10K entries):**
- JSON (current): ~8MB (all in-memory for writes)
- SQL (cursor): ~500KB (streaming)
- **Improvement: 16x reduction**

**Bulk Insert (1K entries):**
- JSON (current): ~200ms (serialize + atomic write)
- SQL (transaction): ~25ms (prepared statements)
- **Improvement: 8x faster**

### B.2 Benchmark Code

```swift
func benchmarkQueries() async throws {
    // JSON benchmark
    let jsonStart = Date()
    let jsonCache = try await legacyStore.load(for: conversationURL)
    let jsonEntries = jsonCache?.entries.values.sorted { $0.timestamp > $1.timestamp }.prefix(50)
    let jsonTime = Date().timeIntervalSince(jsonStart)

    // SQL benchmark
    let sqlStart = Date()
    let sqlEntries = try await sqlRepo.fetchRecent(conversationId: "test", limit: 50)
    let sqlTime = Date().timeIntervalSince(sqlStart)

    print("JSON: \(jsonTime * 1000)ms")
    print("SQL: \(sqlTime * 1000)ms")
    print("Speedup: \(jsonTime / sqlTime)x")
}
```

---

## References

- [GRDB Documentation](https://github.com/groue/GRDB.swift)
- [SQLite WAL Mode](https://www.sqlite.org/wal.html)
- [Swift Concurrency Best Practices](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [macOS App Sandboxing Guide](https://developer.apple.com/documentation/security/app_sandbox)
- [Database Normalization](https://en.wikipedia.org/wiki/Database_normalization)

---

**Document Version:** 1.0
**Last Updated:** 2025-10-10
**Next Review:** After Phase 1 completion
