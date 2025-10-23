# SYSTEM PROMPT FOR LLM REVIEW

You are a senior software architect reviewing a technical analysis of a database integration gap. Your task is to:

1. **Validate the problem diagnosis**: Is the analysis accurate? Are there missing edge cases or overlooked patterns?
2. **Assess the recommendations**: Are the proposed solutions architecturally sound? Do they align with existing patterns in the codebase?
3. **Identify risks**: What could go wrong during implementation? Are there concurrency issues, data migration concerns, or UI state management challenges?
4. **Suggest improvements**: Are there simpler approaches? Can any steps be combined or eliminated?
5. **Check completeness**: Does the brief cover all necessary components (data models, migrations, UI updates, testing)?

Provide feedback in this structure:
- **Strengths**: What is well-analyzed
- **Concerns**: Potential issues or gaps
- **Recommendations**: Alternative approaches or missing steps
- **Risk Assessment**: Migration risks, backwards compatibility, edge cases

---

# Transcript Inventory Database Integration Gap

**Status:** Analysis - Feature Branch
**Branch:** `feature/transcript-inventory-db-integration`
**Issue:** TranscriptInventory uses file-system discovery + in-memory metadata instead of SQL backend
**Impact:** Metadata lost on app restart, no persistent cache, circuit breaker failures

---

## Executive Summary

**Problem**: TranscriptInventoryView discovers transcript sessions from the file system but never persists them to the database. Metadata generation uses an in-memory cache (`SidecarMetadataStore`) with explicit TODO comments indicating it was meant to be replaced with SQL backend. This causes:

1. **No persistence**: Metadata is lost on app restart
2. **No cache reuse**: LLM regenerates metadata on every launch
3. **Circuit breaker errors**: Repeated LLM failures trigger heuristic fallback (seen in logs)
4. **Inconsistent data**: ConversationMonitor uses SQL, TranscriptInventory uses file system

**Expected Behavior**: TranscriptInventory should mirror ConversationMonitor's pattern: discover transcripts → persist to DB → load from DB with cached metadata → display in UI.

**Current State**: Discovery happens, but database write never occurs. TranscriptInventoryWindow calls `monitor.loadAllSessionsFromDatabase()` but DB is empty because no transcripts were saved.

---

## Architecture Comparison

### Working Pattern: ConversationMonitor (Timeline View)

```
┌─────────────────────────────────────────────────────────────┐
│          ConversationMonitor (SQL-Backed)                    │
├─────────────────────────────────────────────────────────────┤
│  1. startMonitoring()                                        │
│     ↓                                                        │
│  2. Initialize TranscriptOrchestrator (SQL backend)          │
│     ↓                                                        │
│  3. getOrCreateProject(name, rootPath) → projectId           │
│     ↓                                                        │
│  4. Background: discoverNewTranscripts()                     │
│     - ConversationSources providers scan file system         │
│     - For each session.fileURL:                              │
│       orchestrator.discoverTranscript(                       │
│         projectId, fileURL, provider, sessionId              │
│       ) → WRITES TO DB                                       │
│     ↓                                                        │
│  5. loadFeedFromSQL()                                        │
│     - orchestrator.getRecentFeed(projectId, limit)           │
│     - Single query: SELECT * FROM entries LEFT JOIN cache    │
│     - Detects cache misses → queues for LLM generation       │
│     ↓                                                        │
│  6. TimelineCacheMissGenerator                               │
│     - Batch LLM generation with rate limiting                │
│     - Save to timeline_cache table (SQL)                     │
│     - Post notification → UI updates in-place                │
└─────────────────────────────────────────────────────────────┘
```

**Key SQL Operations:**
- `discoverTranscript()`: INSERT/UPDATE transcripts table + start file watcher
- `getRecentFeed()`: SELECT with LEFT JOIN on timeline_cache (single query)
- `saveCachedTimeline()`: INSERT/REPLACE into timeline_cache

### Broken Pattern: TranscriptInventory (Inventory View)

```
┌─────────────────────────────────────────────────────────────┐
│       TranscriptInventory (File System + In-Memory)          │
├─────────────────────────────────────────────────────────────┤
│  1. TranscriptInventoryWindow.task { }                       │
│     ↓                                                        │
│  2. monitor.loadAllSessionsFromDatabase()                    │
│     - orchestrator.getTranscripts(projectId)                 │
│     - Returns EMPTY (no transcripts in DB!)                  │
│     ↓                                                        │
│  3. FALLBACK: monitor.allSessions populated by providers     │
│     - ConversationSources.resolveAllSessions()               │
│     - Scans file system (~/.claude/projects, etc.)           │
│     - Returns TranscriptSession objects with file URLs       │
│     ↓                                                        │
│  4. loadMetadataForSessions(sessions)                        │
│     - For each session:                                      │
│       a. Check SidecarMetadataStore.load(fileURL)            │
│          → IN-MEMORY ONLY (no persistence!)                  │
│       b. If miss: TranscriptMetadataOrchestrator             │
│          .ensureMetadata(session)                            │
│          - Parse transcript (TranscriptParser)               │
│          - Generate LLM metadata (circuit breaker active!)   │
│          - Save to SidecarMetadataStore (in-memory)          │
│     ↓                                                        │
│  5. Display metadata in UI                                   │
│     ↓                                                        │
│  6. APP RESTART → metadata lost, LLM regenerates everything  │
└─────────────────────────────────────────────────────────────┘
```

**Missing SQL Operations:**
- ❌ No `discoverTranscript()` call → transcripts never written to DB
- ❌ No SQL-backed metadata cache → SidecarMetadataStore is temp stub
- ❌ No persistence → metadata regenerated on every launch

---

## Expected Architecture (After Fix)

### Complete SQL-Backed Flow

Once the gap is fixed, TranscriptInventory should mirror the ConversationMonitor pattern:

```
┌─────────────────────────────────────────────────────────────┐
│    TranscriptInventory (SQL-Backed) - EXPECTED BEHAVIOR     │
├─────────────────────────────────────────────────────────────┤
│  1. TranscriptInventoryWindow.task { }                       │
│     ↓                                                        │
│  2. PHASE 1: Ensure discoveries are persisted               │
│     - .onChange(of: monitor.allSessions) triggers           │
│     - NEW: persistDiscoveredSessions(sessions)              │
│       For each session:                                      │
│         orchestrator.discoverTranscript(                     │
│           projectId, fileURL, provider, sessionId,           │
│           startWatching: false  // Inventory doesn't watch   │
│         ) → WRITES TO DB ✅                                  │
│     ↓                                                        │
│  3. PHASE 2: Load metadata from SQL backend                 │
│     - loadMetadataForSessions(sessions)                      │
│     - For each session:                                      │
│       a. orchestrator.getTranscriptMetadata(transcriptId)    │
│          → SQL: SELECT * FROM transcript_metadata            │
│       b. IF cache HIT: use cached metadata ✅                │
│       c. IF cache MISS:                                      │
│          - TranscriptMetadataOrchestrator.generateMetadata() │
│          - LLM generation (or heuristic fallback)            │
│          - orchestrator.saveTranscriptMetadata()             │
│            → SQL: INSERT INTO transcript_metadata ✅         │
│     ↓                                                        │
│  4. Display metadata in UI (titles, descriptions, topics)   │
│     ↓                                                        │
│  5. APP RESTART → metadata survives (read from SQL) ✅       │
│     - No duplicate LLM work                                  │
│     - Circuit breaker state persisted                        │
│     - Consistent with ConversationMonitor data               │
└─────────────────────────────────────────────────────────────┘
```

### Added SQL Operations

**New Operation 1: Persist Discovered Transcripts**
```swift
// TranscriptInventoryView.swift
private func persistDiscoveredSessions(_ sessions: [TranscriptSession]) async {
  guard let projectId = monitor.currentProjectId,
        let orchestrator = monitor.orchestrator else { return }

  for session in sessions {
    try? orchestrator.discoverTranscript(
      projectId: projectId,
      fileURL: session.fileURL,
      provider: session.provider.rawValue,
      providerSessionId: session.providerSessionId ?? "",
      startWatching: false  // Inventory doesn't need real-time file watching
    )
  }
}
```

**New Operation 2: Load Metadata from SQL**
```swift
// TranscriptInventoryView.swift (modified)
private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
  guard let orchestrator = monitor.orchestrator else { return }

  for session in sessions {
    let transcriptId = session.identifier

    // Check if already loading
    guard !loadingMetadata.contains(transcriptId) else { continue }

    // Try SQL cache first ✅
    if let cachedMetadata = try? orchestrator.getTranscriptMetadata(transcriptId: transcriptId) {
      await MainActor.run {
        metadata[transcriptId] = cachedMetadata
      }
      continue
    }

    // Cache miss - generate and save to SQL
    await MainActor.run {
      loadingMetadata.insert(transcriptId)
    }

    let task = Task {
      defer {
        Task { @MainActor in
          loadingMetadata.remove(transcriptId)
        }
      }

      // Generate metadata (LLM or heuristic)
      let generatedMetadata = await TranscriptMetadataOrchestrator.shared.metadata(
        for: transcriptId,
        fileURL: session.fileURL
      )

      // Save to SQL (not in-memory) ✅
      try? orchestrator.saveTranscriptMetadata(
        transcriptId: transcriptId,
        metadata: generatedMetadata
      )

      // Update UI
      await MainActor.run {
        metadata[transcriptId] = generatedMetadata
      }
    }

    await MainActor.run {
      metadataTasks[transcriptId] = task
    }
  }
}
```

**New Operation 3: SQL Schema (Already Exists)**
```sql
-- From DatabaseSchema.swift migration v4
CREATE TABLE IF NOT EXISTS transcript_metadata (
  transcript_id TEXT PRIMARY KEY,
  title TEXT,
  description TEXT,
  topics TEXT,  -- JSON array
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);

CREATE INDEX idx_transcript_metadata_transcript_id ON transcript_metadata(transcript_id);
```

### Updated .onChange Handler

**Before (Broken)**:
```swift
.onChange(of: monitor.allSessions) { _, newSessions in
  // Clear selection if selected session no longer exists
  if let selectedId = selectedTranscriptId,
     !newSessions.contains(where: { $0.identifier == selectedId }) {
    selectedTranscriptId = nil
  }

  // Load metadata for new sessions (centralized, not per-row)
  Task {
    await loadMetadataForSessions(newSessions)  // ❌ NO DB WRITE
  }
}
```

**After (Fixed)**:
```swift
.onChange(of: monitor.allSessions) { _, newSessions in
  // Clear selection if selected session no longer exists
  if let selectedId = selectedTranscriptId,
     !newSessions.contains(where: { $0.identifier == selectedId }) {
    selectedTranscriptId = nil
  }

  // PHASE 1: Persist discovered sessions to database ✅
  Task {
    await persistDiscoveredSessions(newSessions)
  }

  // PHASE 2: Load metadata from SQL (not in-memory) ✅
  Task {
    await loadMetadataForSessions(newSessions)
  }
}
```

### Before/After Comparison

| Aspect | Before (Broken) | After (Fixed) |
|--------|-----------------|---------------|
| **Discovery Persistence** | ❌ Not saved to DB | ✅ orchestrator.discoverTranscript() |
| **Metadata Cache** | ❌ In-memory (SidecarMetadataStore) | ✅ SQL (transcript_metadata table) |
| **Survives Restart** | ❌ No (regenerates all) | ✅ Yes (reads from SQL) |
| **LLM Quota** | ❌ Wasted (duplicate work) | ✅ Efficient (cache reuse) |
| **Circuit Breaker State** | ❌ Lost on restart | ✅ Persisted in SQL |
| **Consistency** | ❌ Out of sync with ConversationMonitor | ✅ Same SQL backend |
| **Performance (Restart)** | ❌ Slow (1-3s LLM per session) | ✅ Fast (~1ms SQL read) |

### Migration Checklist

To achieve the expected architecture, the following changes are required:

**Phase 1: Add Discovery Persistence**
- [ ] Add `persistDiscoveredSessions()` method to TranscriptInventoryView
- [ ] Update `.onChange(of: monitor.allSessions)` to call persist before load
- [ ] Test: Verify transcripts appear in `transcripts` table after discovery

**Phase 2: Migrate Metadata to SQL**
- [ ] Update `loadMetadataForSessions()` to call `orchestrator.getTranscriptMetadata()`
- [ ] Update metadata generation to call `orchestrator.saveTranscriptMetadata()`
- [ ] Remove `SidecarMetadataStore` (or mark deprecated)
- [ ] Test: Verify metadata survives app restart

**Phase 3: Update TranscriptMetadataOrchestrator**
- [ ] Modify to use SQL backend instead of in-memory store
- [ ] Persist circuit breaker state to database (or preferences)
- [ ] Test: Verify circuit breaker survives restart

**Phase 4: Verify Consistency**
- [ ] Compare `monitor.allSessions` (from SQL) with filesystem scan
- [ ] Ensure no orphaned entries in UI
- [ ] Test: Switch project, verify inventory updates correctly

### Expected Benefits

After implementing the fix:

1. **No Metadata Loss**: Transcript titles/descriptions persist across app restarts
2. **Reduced LLM Quota Usage**: Metadata generated once, reused forever (unless content changes)
3. **Consistent Data**: Inventory and Timeline use same SQL backend
4. **Faster Startup**: No LLM regeneration on launch (instant SQL reads)
5. **Circuit Breaker Resilience**: Learns from failures, avoids repeated LLM errors
6. **Simplified Code**: Remove temporary in-memory cache, use established SQL patterns

---

## Root Cause Analysis

### 1. SidecarMetadataStore is a Stub

**File**: `Contextify/Contextify/SidecarMetadataStore.swift`

```swift
//  Temporary stub for metadata storage during SQL migration
//  TODO: Migrate to SQL backend (see sql-integration-plan-v2.md Part 7)

actor SidecarMetadataStore {
  private var cache: [URL: TranscriptMetadata] = [:]  // IN-MEMORY ONLY!

  func load(for url: URL) -> TranscriptMetadata? {
    return cache[url]  // Returns nil after app restart
  }

  func save(_ metadata: TranscriptMetadata, for url: URL) {
    cache[url] = metadata  // Lost on app termination
  }
}
```

**Evidence**: File header comment explicitly states this is temporary. No persistence layer.

### 2. TranscriptInventory Never Calls `discoverTranscript()`

**File**: `Contextify/Contextify/TranscriptInventoryView.swift:129-136`

```swift
.onChange(of: monitor.allSessions) { _, newSessions in
  // Load metadata for new sessions
  Task {
    await loadMetadataForSessions(newSessions)  // ❌ No DB write!
  }
}
```

**Missing Code**: Should call `orchestrator.discoverTranscript()` for each session to persist to DB.

**Comparison** (ConversationMonitor pattern):

```swift
// ConversationMonitor.swift:204-206
for session in sessions {
  try orchestrator.discoverTranscript(
    projectId: projectId,
    fileURL: session.fileURL,
    provider: session.provider,
    providerSessionId: session.providerSessionId,
    startWatching: true  // ✅ Persists to DB + starts file watcher
  )
}
```

### 3. Circuit Breaker Triggering Repeatedly

**Log Evidence** (`/tmp/contextify-02.log`):

```
error 15:53:28.254329-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.296843-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.345612-0700 Contextify Circuit breaker active, using heuristic fallback
[... 10+ occurrences]
```

**Root Cause**: TranscriptMetadataOrchestrator repeatedly calls LLM for metadata generation without SQL cache. Failures accumulate, circuit breaker opens, heuristic fallback used.

**Circuit Breaker Logic** (`TranscriptMetadataOrchestrator.swift:288-298`):

```swift
private func shouldUseCircuitBreaker() -> Bool {
  let ratio = Double(failureCount) / Double(total)
  // Open circuit if failure ratio >= 60% and >= 5 requests
  return ratio >= 0.6 && total >= 5
}
```

**Analysis**: Without SQL cache, every transcript triggers fresh LLM call. If 3 out of 5 fail → circuit breaker opens → all subsequent calls use heuristic (generic "Developer Chat" titles).

---

## Data Flow Gap

### Expected Flow (Mirroring ConversationMonitor)

```
File System Scan
      ↓
ConversationSources.sessions(for: context)
      ↓
For each TranscriptSession:
  orchestrator.discoverTranscript(...)  ← WRITE TO DB
      ↓
DB Query: orchestrator.getTranscripts(projectId)
      ↓
Map to TranscriptSession objects
      ↓
For each session:
  Check DB for cached metadata
      ↓
  If cache miss:
    - Queue for LLM generation (TimelineCacheMissGenerator)
    - Display fallback summary in UI
      ↓
  When LLM completes:
    - Save to timeline_cache (SQL)
    - Post notification
    - UI updates in-place
```

### Actual Flow (Current Broken State)

```
File System Scan
      ↓
ConversationSources.sessions(for: context)
      ↓
❌ NO DB WRITE (transcripts never persisted)
      ↓
TranscriptInventoryView displays sessions
      ↓
For each session:
  Check SidecarMetadataStore (in-memory)
      ↓
  Always miss (after app restart)
      ↓
  TranscriptMetadataOrchestrator.ensureMetadata()
    - Parse entire transcript
    - Call LLM (circuit breaker triggers)
    - Save to in-memory cache
      ↓
  Display metadata
      ↓
  APP RESTART → lost, repeat cycle
```

---

## Component Analysis

### 1. ConversationSources (File System Discovery)

**Purpose**: Scan file system for transcript files (Claude Code, Codex CLI)

**Files**:
- `Contextify/Contextify/ConversationSources.swift`: Provider implementations

**Logic**:
- `ClaudeTranscriptProvider`: Scans `~/.claude/projects/{project-dir}/` for `*.jsonl`
- `CodexTranscriptProvider`: Scans `~/.codex/sessions/` recursively, matches by `cwd` or `git.repository_url`

**Status**: ✅ **Working correctly** - discovery logic is sound

**Relationship to Problem**: This is the starting point. Discovery works, but persistence step is missing.

### 2. TranscriptOrchestrator (SQL Backend)

**Purpose**: Coordinate all database operations (projects, transcripts, entries, cache)

**Files**:
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`: Main coordinator
- `app/Sources/ContextifyCore/Database/Repositories.swift`: Type-safe GRDB repositories

**Key Methods**:
- `discoverTranscript(projectId, fileURL, provider, providerSessionId, startWatching)`: INSERT transcript + start file watcher
- `getTranscripts(forProject:)`: SELECT all transcripts for project
- `getRecentFeed(forProject, limit, generatorSignature)`: SELECT entries with LEFT JOIN on timeline_cache
- `saveCachedTimeline(cache)`: INSERT/REPLACE into timeline_cache

**Status**: ✅ **Implemented and working** - used by ConversationMonitor

**Relationship to Problem**: TranscriptInventory never calls these methods (except `getTranscripts` which returns empty).

### 3. SidecarMetadataStore (In-Memory Cache)

**Purpose**: ❌ **Temporary stub** - was supposed to be replaced with SQL backend

**Files**:
- `Contextify/Contextify/SidecarMetadataStore.swift`: In-memory dictionary

**Logic**:
- `load(for: URL) -> TranscriptMetadata?`: Returns from in-memory cache
- `save(metadata, for: URL)`: Stores in-memory (no persistence)

**Status**: 🚨 **Broken by design** - explicit TODO: "Migrate to SQL backend"

**Relationship to Problem**: This is the core issue. Metadata stored here is lost on restart.

### 4. TranscriptMetadataOrchestrator (LLM Metadata Generation)

**Purpose**: Generate title/description/topics for transcript sessions using LLM

**Files**:
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`: Actor-based orchestrator

**Logic**:
- Parse transcript into exchanges (TranscriptParser)
- Build context with sampling strategy (ContextBuilder)
- Call FoundationLLM for generation
- Circuit breaker pattern (60% failure threshold)
- Save to SidecarMetadataStore (in-memory!)

**Status**: ⚠️ **Partially working** - generates metadata but saves to wrong place

**Relationship to Problem**: Should save to SQL timeline_cache, not SidecarMetadataStore.

### 5. TranscriptInventoryView (UI Layer)

**Purpose**: Display all discovered transcripts with metadata

**Files**:
- `Contextify/Contextify/TranscriptInventoryView.swift`: Main UI component
- `Contextify/Contextify/TranscriptInventoryWindow.swift`: Window wrapper

**Logic**:
- Window task calls `monitor.loadAllSessionsFromDatabase()` (returns empty)
- Falls back to `monitor.allSessions` (populated by ConversationSources providers)
- `loadMetadataForSessions()` triggers TranscriptMetadataOrchestrator

**Status**: ⚠️ **Displays data but doesn't persist** - missing DB write step

**Relationship to Problem**: This is where the DB write should happen (or delegate to ConversationMonitor).

### 6. ConversationMonitor (State Manager)

**Purpose**: Manage timeline state, session switching, DB queries

**Files**:
- `Contextify/Contextify/ConversationMonitor.swift`: Main actor-based singleton

**Key Methods**:
- `startMonitoring()`: Initialize TranscriptOrchestrator, start discovery loop
- `discoverNewTranscripts()`: Background task that calls `orchestrator.discoverTranscript()` ✅
- `loadFeedFromSQL()`: Query entries with cache, queue misses for LLM ✅
- `loadAllSessionsFromDatabase()`: Query transcripts, map to TranscriptSession objects ✅
- `switchToSessionFromUser(session)`: Switch active session for timeline filtering ✅

**Status**: ✅ **Fully working** - reference implementation for correct pattern

**Relationship to Problem**: TranscriptInventory should reuse this pattern.

---

## File Relationship Map

| File Path | Purpose | Relationship to Problem |
|-----------|---------|-------------------------|
| `Contextify/Contextify/TranscriptInventoryView.swift` | UI for browsing sessions | ❌ Missing DB write in `loadMetadataForSessions()` |
| `Contextify/Contextify/TranscriptInventoryWindow.swift` | Window wrapper | Calls `loadAllSessionsFromDatabase()` which returns empty |
| `Contextify/Contextify/ConversationSources.swift` | File system discovery | ✅ Working - scans for transcripts |
| `Contextify/Contextify/ConversationMonitor.swift` | State manager + DB orchestration | ✅ Reference pattern - should be reused |
| `Contextify/Contextify/SidecarMetadataStore.swift` | In-memory metadata cache | 🚨 **ROOT CAUSE** - temp stub, no persistence |
| `Contextify/Contextify/TranscriptMetadataOrchestrator.swift` | LLM metadata generation | ⚠️ Saves to wrong place (in-memory vs SQL) |
| `Contextify/Contextify/TranscriptParser.swift` | Parse JSONL transcripts | ✅ Working - used by metadata generation |
| `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift` | SQL backend coordinator | ✅ Implemented - not called by TranscriptInventory |
| `app/Sources/ContextifyCore/Database/Repositories.swift` | GRDB repositories | ✅ Implemented - ready to use |
| `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` | SQL schema definitions | ✅ Has transcript_metadata table (unused?) |

---

## Recommendations

### Phase 1: Persist Discovered Transcripts to Database

**Goal**: Ensure all discovered transcripts are written to DB before metadata generation.

**Implementation**:

1. **Add discovery loop to TranscriptInventoryView** (or reuse ConversationMonitor's):

```swift
// TranscriptInventoryView.swift (new method)
@MainActor
private func persistDiscoveredSessions(_ sessions: [TranscriptSession]) async {
  guard let projectId = monitor.currentProjectId,
        let orchestrator = monitor.orchestrator else {
    return
  }

  for session in sessions {
    do {
      try orchestrator.discoverTranscript(
        projectId: projectId,
        fileURL: session.fileURL,
        provider: session.provider.rawValue,
        providerSessionId: session.identifier,
        startWatching: false  // Inventory view doesn't need file watching
      )
    } catch {
      // Log but don't fail - continue with other sessions
    }
  }
}
```

2. **Update `onChange` handler**:

```swift
.onChange(of: monitor.allSessions) { _, newSessions in
  Task {
    // Persist to DB first
    await persistDiscoveredSessions(newSessions)

    // Then load metadata
    await loadMetadataForSessions(newSessions)
  }
}
```

3. **Update `task` handler**:

```swift
.task {
  // Persist current sessions to DB
  await persistDiscoveredSessions(monitor.allSessions)

  // Then load metadata
  await loadMetadataForSessions(monitor.allSessions)
}
```

**Risk**: Duplicate transcript entries if discovery runs multiple times. Mitigation: `discoverTranscript()` uses `INSERT OR REPLACE` (idempotent).

---

### Phase 2: Migrate Metadata Storage to SQL

**Goal**: Replace SidecarMetadataStore with SQL-backed cache (reuse timeline_cache table or add transcript_metadata table).

**Option A: Reuse timeline_cache table**

**Pros**:
- Already implemented and working
- Integrated with TimelineCacheMissGenerator
- No schema changes needed

**Cons**:
- timeline_cache is keyed by (content_sha256, window_sha256) - designed for timeline entries, not whole transcript metadata
- Semantic mismatch: timeline_cache stores entry-level summaries, not session-level metadata

**Option B: Use dedicated transcript_metadata table**

**Pros**:
- Semantic clarity: session-level metadata separate from entry-level cache
- Can store richer metadata (topics array, confidence scores)
- Simpler queries (no composite key juggling)

**Cons**:
- Requires schema migration
- Need to implement save/load logic in TranscriptOrchestrator

**Recommendation**: **Option B** - dedicated table for clarity.

**Schema** (check if already exists):

```sql
CREATE TABLE IF NOT EXISTS transcript_metadata (
  transcript_id TEXT PRIMARY KEY NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  topics TEXT NOT NULL,  -- JSON array
  confidence REAL NOT NULL,
  strategy TEXT NOT NULL,
  model TEXT NOT NULL,
  message_count INTEGER NOT NULL,
  latency_ms INTEGER NOT NULL,
  needs_review INTEGER NOT NULL DEFAULT 0,
  prompt_version INTEGER NOT NULL,
  generator_version INTEGER NOT NULL,
  transcript_sha256 TEXT NOT NULL,
  generated_at INTEGER NOT NULL,
  FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
);
```

**TranscriptOrchestrator Methods**:

```swift
// Save metadata
func saveTranscriptMetadata(
  transcriptId: String,
  metadata: TranscriptMetadata
) throws {
  try metadataRepository.save(transcriptId: transcriptId, metadata: metadata)
}

// Load metadata
func getTranscriptMetadata(
  transcriptId: String
) throws -> TranscriptMetadata? {
  return try metadataRepository.get(transcriptId: transcriptId)
}

// Batch load for inventory view
func getTranscriptMetadataBatch(
  transcriptIds: [String]
) throws -> [String: TranscriptMetadata] {
  return try metadataRepository.getBatch(transcriptIds: transcriptIds)
}
```

**Update TranscriptMetadataOrchestrator**:

```swift
// Replace SidecarMetadataStore with SQL backend
private let orchestrator: TranscriptOrchestrator

func ensureMetadata(
  for session: TranscriptSession,
  forceRegenerate: Bool = false
) async throws -> TranscriptMetadata {
  // Check SQL cache (not in-memory!)
  if !forceRegenerate,
     let transcriptId = getTranscriptId(for: session),
     let cached = try? orchestrator.getTranscriptMetadata(transcriptId: transcriptId),
     isFresh(cached, for: session.fileURL) {
    return cached
  }

  // Generate metadata...
  let metadata = try await generateMetadata(for: session, forceRegenerate: forceRegenerate)

  // Save to SQL (not in-memory!)
  if let transcriptId = getTranscriptId(for: session) {
    try orchestrator.saveTranscriptMetadata(transcriptId: transcriptId, metadata: metadata)
  }

  return metadata
}
```

**Risk**: Schema migration could fail on existing databases. Mitigation: Use migration version check, handle gracefully.

---

### Phase 3: Batch Metadata Loading in Inventory View

**Goal**: Load metadata efficiently from SQL instead of triggering LLM for every session.

**Implementation**:

```swift
// TranscriptInventoryView.swift
@MainActor
private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
  guard let orchestrator = monitor.orchestrator else { return }

  // Batch query SQL for all metadata
  let transcriptIds = sessions.compactMap { getTranscriptId(for: $0) }
  let cachedMetadata = try? orchestrator.getTranscriptMetadataBatch(transcriptIds: transcriptIds)

  // Populate metadata dictionary with cached values
  for session in sessions {
    guard let transcriptId = getTranscriptId(for: session) else { continue }

    if let cached = cachedMetadata?[transcriptId] {
      metadata[session.fileURL] = cached
    } else {
      // Cache miss - trigger generation
      loadingMetadata.insert(session.fileURL)
      Task {
        defer { loadingMetadata.remove(session.fileURL) }
        do {
          let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
          metadata[session.fileURL] = generated
        } catch {
          // Failed - show placeholder
        }
      }
    }
  }
}
```

**Risk**: Metadata generation could still overwhelm LLM. Mitigation: Reuse TimelineCacheMissGenerator pattern with batching/rate limiting.

---

### Phase 4: Consolidate Metadata Generation

**Goal**: Unify timeline entry summaries and transcript session metadata under single LLM pipeline.

**Current State**:
- Timeline entries: TimelineCacheMissGenerator → timeline_cache table
- Transcript sessions: TranscriptMetadataOrchestrator → SidecarMetadataStore (in-memory)

**Proposed State**:
- Timeline entries: TimelineCacheMissGenerator → timeline_cache table (unchanged)
- Transcript sessions: **New TranscriptMetadataGenerator** → transcript_metadata table

**Implementation**:

```swift
/// Actor-based metadata generator for transcript sessions (mirrors TimelineCacheMissGenerator)
actor TranscriptMetadataGenerator {
  private let orchestrator: TranscriptOrchestrator
  private let llm: TranscriptMetadataLLM
  private var pendingMetadata: [String: TranscriptSession] = [:]  // Keyed by transcript ID
  private var generationTask: Task<Void, Never>?

  func queueMetadata(for sessions: [TranscriptSession]) {
    for session in sessions {
      guard let transcriptId = getTranscriptId(for: session) else { continue }
      pendingMetadata[transcriptId] = session
    }

    if generationTask == nil {
      generationTask = Task { await processQueue() }
    }
  }

  private func processQueue() async {
    while !pendingMetadata.isEmpty {
      let batch = Array(pendingMetadata.prefix(5))  // Batch size 5
      for (transcriptId, session) in batch {
        pendingMetadata.removeValue(forKey: transcriptId)

        do {
          // Parse transcript
          let exchanges = try TranscriptParser().parseExchanges(url: session.fileURL)

          // Generate metadata via LLM
          let metadata = try await llm.singlePass(context: buildContext(exchanges), ...)

          // Save to SQL
          try orchestrator.saveTranscriptMetadata(transcriptId: transcriptId, metadata: metadata)

          // Post notification
          NotificationCenter.default.post(name: .transcriptMetadataUpdated, object: transcriptId)
        } catch {
          // Log and continue
        }
      }

      // Rate limit
      try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2s
    }
  }
}
```

**Risk**: Duplicate LLM infrastructure. Mitigation: Share FoundationLLM session controllers between generators.

---

## Migration Plan

### Step 1: Verify Schema

**Action**: Check if `transcript_metadata` table already exists in schema.

```bash
# Search schema file
grep -n "transcript_metadata" app/Sources/ContextifyCore/Database/DatabaseSchema.swift
```

**If missing**: Add migration in `DatabaseSchema.swift`.

---

### Step 2: Update TranscriptOrchestrator

**Action**: Add methods for transcript metadata save/load.

**Files to modify**:
- `app/Sources/ContextifyCore/Database/TranscriptOrchestrator.swift`
- `app/Sources/ContextifyCore/Database/Repositories.swift` (add TranscriptMetadataRepository)

---

### Step 3: Replace SidecarMetadataStore Usage

**Action**: Update TranscriptMetadataOrchestrator to use SQL backend.

**Files to modify**:
- `Contextify/Contextify/TranscriptMetadataOrchestrator.swift`

**Changes**:
- Replace `store = SidecarMetadataStore()` with `orchestrator = TranscriptOrchestrator.shared`
- Update `ensureMetadata()` to query/save SQL instead of in-memory cache

---

### Step 4: Persist Discovered Transcripts

**Action**: Call `orchestrator.discoverTranscript()` in TranscriptInventoryView.

**Files to modify**:
- `Contextify/Contextify/TranscriptInventoryView.swift`

**Changes**:
- Add `persistDiscoveredSessions()` method (see Phase 1 implementation)
- Update `onChange` and `task` handlers to call it

---

### Step 5: Batch Load Metadata in UI

**Action**: Replace sequential LLM calls with batch SQL query.

**Files to modify**:
- `Contextify/Contextify/TranscriptInventoryView.swift`

**Changes**:
- Update `loadMetadataForSessions()` to use `getTranscriptMetadataBatch()` (see Phase 3 implementation)

---

### Step 6: Testing

**Actions**:
1. Clean DB: `make clean-db`
2. Launch app, verify transcripts are persisted to DB
3. Check logs: No circuit breaker errors
4. Restart app, verify metadata loads from DB (no LLM calls)
5. Switch between sessions, verify timeline entries load correctly

---

### Step 7: Remove SidecarMetadataStore

**Action**: Delete temporary stub after migration complete.

**Files to delete**:
- `Contextify/Contextify/SidecarMetadataStore.swift`

**Files to update**:
- Remove imports and references in TranscriptMetadataOrchestrator

---

## Testing Strategy

### Unit Tests

1. **TranscriptOrchestrator.saveTranscriptMetadata()**
   - Insert new metadata
   - Update existing metadata
   - Verify foreign key constraint (transcript must exist)

2. **TranscriptOrchestrator.getTranscriptMetadata()**
   - Load by transcript ID
   - Return nil if not found
   - Batch load multiple IDs

3. **TranscriptInventoryView.persistDiscoveredSessions()**
   - Mock orchestrator.discoverTranscript()
   - Verify called for each session
   - Handle errors gracefully

### Integration Tests

1. **Full flow: Discovery → Persist → Load → Display**
   - Scan file system
   - Persist transcripts to DB
   - Load metadata from SQL
   - Display in UI without LLM calls

2. **Metadata cache invalidation**
   - Modify transcript file
   - Verify metadata regenerates
   - Verify new metadata saved to SQL

3. **Session switching**
   - Switch between sessions in inventory
   - Verify timeline entries load correctly
   - Verify metadata displayed in detail view

### Manual Testing

1. **Clean state**:
   ```bash
   make clean-db
   make build
   # Launch app
   ```

2. **Verify persistence**:
   - Open inventory window
   - Check logs: "Loaded N sessions from database"
   - Restart app
   - Check logs: No LLM generation, metadata loaded from SQL

3. **Verify circuit breaker fixed**:
   - Monitor logs during inventory loading
   - Should see: "Using cached metadata" (not "Circuit breaker active")

---

## Cross-References

- **SQL Backend Architecture**: `build/notes/technical-reference/sql-backend-architecture.md`
- **Timeline Cache + LLM Integration**: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **ConversationMonitor State Management**: `build/notes/technical-reference/conversation-monitor-state-architecture.md`
- **Database Usage Guide**: `app/Sources/ContextifyCore/Database/README.md`

---

## UI Enhancement: Inventory Window Icon

**Goal**: Surface Transcript Inventory window via icon next to session dropdown.

**Current State**: No visible UI affordance for inventory window.

**Proposed Design**:

```
┌─────────────────────────────────────────┐
│  [🗂️] [Current Session ▼]               │  ← Header row
└─────────────────────────────────────────┘
    ↑
   New icon button
```

**Implementation**:

1. **Add button to ContentView.swift header**:

```swift
HStack {
  // New: Inventory icon button
  Button {
    openInventoryWindow()
  } label: {
    Image(systemName: "tray.full")  // or "list.bullet.rectangle"
      .help("Browse All Transcripts")
  }
  .buttonStyle(.borderless)

  // Existing: Session dropdown
  Menu {
    ForEach(monitor.allSessions, id: \.fileURL) { session in
      Button(session.identifier) {
        Task { await monitor.switchToSessionFromUser(session) }
      }
    }
  } label: {
    HStack {
      Text(monitor.activeSession?.identifier ?? "No Session")
      Image(systemName: "chevron.down")
    }
  }
}
```

2. **Add window opener method**:

```swift
private func openInventoryWindow() {
  // Use existing window management
  if let window = NSApp.windows.first(where: { $0.title == "Transcript Inventory" }) {
    window.makeKeyAndOrderFront(nil)
  } else {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Transcript Inventory"
    window.contentView = NSHostingView(rootView: TranscriptInventoryWindow())
    window.center()
    window.makeKeyAndOrderFront(nil)
  }
}
```

**Icon Options**:
- `tray.full`: Suggests collection/storage
- `list.bullet.rectangle`: Suggests inventory/list view
- `folder.fill.badge.gearshape`: Suggests managed transcripts

---

## Appendix: Pertinent Log Entries

**Source**: `/tmp/contextify-02.log`

**Circuit Breaker Errors** (repeated):

```
error 15:53:28.254329-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.296843-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.345612-0700 Contextify Circuit breaker active, using heuristic fallback
```

**Analysis**: TranscriptMetadataOrchestrator's circuit breaker opened after repeated LLM failures. All subsequent metadata requests use heuristic fallback (generic titles like "Developer Chat").

**Root Cause**: No SQL cache → every inventory load triggers fresh LLM calls → failures accumulate → circuit breaker opens.

**Expected After Fix**: Should see "Using cached metadata for {session}" (no LLM calls after first generation).

---

**End of Technical Brief**

---

# APPENDIX: Complete File Contents

## File: Contextify/Contextify/TranscriptInventoryView.swift

```swift
import SwiftUI
import ContextifyCore

/// Displays all discovered transcripts for the current project, including worktrees.
/// Uses HSplitView for macOS-native sidebar + detail layout.
struct TranscriptInventoryView: View {
  @Environment(ConversationMonitor.self) private var monitor
  let onSelectSession: (TranscriptSession) -> Void

  @State private var selectedSessionURL: URL?
  @State private var searchText = ""
  @State private var groupingMode: GroupingMode = .provider
  @State private var metadata: [URL: TranscriptMetadata] = [:]
  @State private var loadingMetadata: Set<URL> = []
  @State private var showingFlushAlert = false
  @State private var lastFlushCount = 0

  enum GroupingMode: String, CaseIterable, Identifiable {
    case provider = "Provider"
    case date = "Date"
    case flat = "All"

    var id: String { rawValue }
  }

  var body: some View {
    Group {
      if let error = monitor.lastError, monitor.allSessions.isEmpty {
        // Show error when no transcripts found
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("Unable to Load Transcripts")
            .font(.headline)
          Text(error)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        HSplitView {
          // Session list
          sessionListView
            .frame(minWidth: 250)

          // Detail view
          detailView
            .frame(minWidth: 500)
        }
      }
    }
  }

  private var selectedSession: TranscriptSession? {
    guard let url = selectedSessionURL else { return nil }
    return monitor.allSessions.first(where: { $0.fileURL == url })
  }

  @ViewBuilder
  private var sessionListView: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Transcript Inventory")
          .font(.headline)
        Spacer()

        Button {
          flushHeuristicCache()
        } label: {
          Label("Flush Heuristic Cache", systemImage: "trash")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Delete cached metadata for \"Developer Chat\" and \"Brief Session\" titles")

        Button {
          refreshSessions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
      }
      .padding()
      .alert("Cache Flushed", isPresented: $showingFlushAlert) {
        Button("OK") { }
      } message: {
        Text("Flushed \(lastFlushCount) heuristic metadata files. The transcripts will be re-analyzed automatically.")
      }

      // Toolbar with grouping
      HStack {
        Picker("Group by", selection: $groupingMode) {
          ForEach(GroupingMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)

        Spacer()

        Text("\(filteredSessions.count) transcripts")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal)
      .padding(.bottom, 8)

      Divider()

      // Session list with URL-based selection
      List(monitor.allSessions, id: \.fileURL, selection: $selectedSessionURL) { session in
        sessionRow(session)
          .tag(session.fileURL)
      }
      .listStyle(.sidebar)
      .searchable(text: $searchText, prompt: "Search transcripts")
      .onChange(of: monitor.allSessions) { _, newSessions in
        // Clear selection if selected session no longer exists
        if let selectedURL = selectedSessionURL,
           !newSessions.contains(where: { $0.fileURL == selectedURL }) {
          selectedSessionURL = nil
        }

        // Load metadata for new sessions
        Task {
          await loadMetadataForSessions(newSessions)
        }
      }
      .task {
        // Load metadata on initial appearance
        await loadMetadataForSessions(monitor.allSessions)
      }
      .onReceive(NotificationCenter.default.publisher(for: .revealTranscript)) { notification in
        guard let path = notification.userInfo?["path"] as? String else { return }

        // Find session with matching path
        if let session = monitor.allSessions.first(where: { $0.fileURL.path == path }) {
          // Select the session
          selectedSessionURL = session.fileURL

          // TODO: Add scroll-to-item logic when List supports programmatic scrolling
        }
      }
    }
  }

  @ViewBuilder
  private var detailView: some View {
    if let session = selectedSession {
      TranscriptDetailView(
        session: session,
        isActive: session.fileURL == monitor.activeSession?.fileURL,
        onSelect: {
          onSelectSession(session)
        },
        onMetadataUpdate: { url, newMetadata in
          metadata[url] = newMetadata
        }
      )
    } else {
      emptyDetailView
    }
  }

  private var emptyDetailView: some View {
    VStack(spacing: 12) {
      Image(systemName: "doc.text")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text("No Transcript Selected")
        .font(.headline)
      Text("Select a transcript from the sidebar to view details")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Session Row

  @ViewBuilder
  private func sessionRow(_ session: TranscriptSession) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: providerIcon(session.provider))
          .foregroundStyle(providerColor(session.provider))
          .frame(width: 16)

        if let meta = metadata[session.fileURL] {
          Text(meta.title)
            .font(.callout)
            .lineLimit(1)
        } else if loadingMetadata.contains(session.fileURL) {
          HStack(spacing: 4) {
            ProgressView()
              .controlSize(.mini)
              .scaleEffect(0.7)
              .frame(width: 10, height: 10)
            Text("Analyzing…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          Text(session.identifier)
            .font(.callout)
            .lineLimit(1)
        }

        Spacer()

        if session.fileURL == monitor.activeSession?.fileURL {
          Image(systemName: "circle.fill")
            .font(.system(size: 6))
            .foregroundStyle(.green)
        }
      }

      if let meta = metadata[session.fileURL] {
        // Description (2 lines)
        Text(meta.description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }

      HStack(spacing: 4) {
        Label(providerName(session.provider), systemImage: providerIcon(session.provider))
          .font(.caption)
          .foregroundStyle(.secondary)
          .labelStyle(.titleOnly)

        Text("•")
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(relativeTime(session.lastActivity))
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        // Topic chips (max 2)
        if let meta = metadata[session.fileURL] {
          HStack(spacing: 4) {
            ForEach(meta.topics.prefix(2), id: \.self) { topic in
              Text(topic)
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())
            }
          }
        }
      }
    }
    .padding(.vertical, 4)
  }

  // MARK: - Helpers

  private var filteredSessions: [TranscriptSession] {
    let sessions = monitor.allSessions
    if searchText.isEmpty {
      return sessions
    }
    return sessions.filter { session in
      session.identifier.localizedCaseInsensitiveContains(searchText)
        || session.fileURL.path.localizedCaseInsensitiveContains(searchText)
    }
  }

  private func providerName(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func providerIcon(_ provider: TimelineSourceContext.Provider) -> String {
    switch provider {
    case .claudeCode: return "terminal.fill"
    case .codexCLI: return "chevron.left.forwardslash.chevron.right"
    case .other: return "doc.text"
    }
  }

  private func providerColor(_ provider: TimelineSourceContext.Provider) -> Color {
    switch provider {
    case .claudeCode: return .orange
    case .codexCLI: return .blue
    case .other: return .gray
    }
  }

  private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private func refreshSessions() {
    // Refresh handled by window wrapper via monitor.refresh()
  }

  private func flushHeuristicCache() {
    Task { @MainActor in
      let store = SidecarMetadataStore()
      let flushedCount = await store.flushHeuristicMetadata(for: monitor.allSessions)

      if flushedCount > 0 {
        lastFlushCount = flushedCount
        showingFlushAlert = true

        // Clear in-memory cache and trigger regeneration for flushed items
        for session in monitor.allSessions {
          if let meta = metadata[session.fileURL],
             meta.model == "heuristic" ||
             meta.title == "Developer Chat" ||
             meta.title == "Brief Session" {
            metadata.removeValue(forKey: session.fileURL)
            loadingMetadata.insert(session.fileURL)

            Task { @MainActor in
              defer { loadingMetadata.remove(session.fileURL) }
              do {
                let newMeta = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
                  for: session,
                  forceRegenerate: true
                )
                metadata[session.fileURL] = newMeta
              } catch {
                // Failed to regenerate, loading indicator removed by defer
              }
            }
          }
        }
      }
    }
  }

  @MainActor
  private func loadMetadataForSessions(_ sessions: [TranscriptSession]) async {
    for session in sessions {
      // Skip if already loaded or loading
      guard metadata[session.fileURL] == nil,
            !loadingMetadata.contains(session.fileURL) else {
        continue
      }

      // Check for cached metadata first
      let store = SidecarMetadataStore()
      if let cached = await store.load(for: session.fileURL) {
        metadata[session.fileURL] = cached
        continue
      }

      // Trigger generation
      loadingMetadata.insert(session.fileURL)

      Task { @MainActor in
        defer { loadingMetadata.remove(session.fileURL) }
        do {
          let generated = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
          metadata[session.fileURL] = generated
        } catch {
          // Failed to generate, loading indicator removed by defer
        }
      }
    }
  }
}

/// Detail view for a selected transcript session
struct TranscriptDetailView: View {
  let session: TranscriptSession
  let isActive: Bool
  let onSelect: () -> Void
  let onMetadataUpdate: ((URL, TranscriptMetadata) -> Void)?

  @State private var metadata: TranscriptMetadata?
  @State private var isRegenerating = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with status badge
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            // Use metadata title if available, otherwise fall back to identifier
            Text(metadata?.title ?? session.identifier)
              .font(.title2)
              .fontWeight(.semibold)

            // Show description if available, otherwise show provider + filename
            if let meta = metadata, !meta.description.isEmpty {
              Text(meta.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            } else {
              Text("\(providerName) • \(session.fileURL.lastPathComponent)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()

          if isActive {
            Label("Active", systemImage: "circle.fill")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 4)
              .background(Color.green)
              .clipShape(Capsule())
          }
        }

        Divider()

        // Transcript Details (File Info + LLM metadata if available)
        VStack(alignment: .leading, spacing: 12) {
          Text("Transcript Details")
            .font(.headline)

          // Include Title and Description from LLM metadata if available
          if let meta = metadata {
            metadataRow(label: "Title", value: meta.title)
            metadataRow(label: "Description", value: meta.description)
          }

          metadataRow(label: "Last Modified", value: formattedDate(session.lastActivity))

          // File Path with Finder reveal button
          HStack(alignment: .top) {
            Text("File Path")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(width: 100, alignment: .leading)

            Text(session.fileURL.path)
              .font(.subheadline)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)

            Button {
              NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
            } label: {
              Image(systemName: "folder")
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
          }

          metadataRow(label: "File Name", value: session.fileURL.lastPathComponent)
          metadataRow(label: "Provider", value: providerName)

          if let fileSize = fileSize() {
            metadataRow(label: "File Size", value: fileSize)
          }

          if let lineCount = lineCount() {
            metadataRow(label: "Lines", value: "\(lineCount)")
          }
        }

        Divider()

        // AI-Generated Metadata
        if let meta = metadata {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("AI Summary")
                .font(.headline)

              if meta.needsReview {
                Text("Needs Review")
                  .font(.caption)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.orange)
                  .clipShape(Capsule())
              }

              if meta.promptVersion < 2 {
                Text("Stale")
                  .font(.caption)
                  .foregroundStyle(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 2)
                  .background(Color.yellow)
                  .clipShape(Capsule())
              }

              Spacer()

              Button {
                Task {
                  await regenerateMetadata()
                }
              } label: {
                HStack(spacing: 4) {
                  if isRegenerating {
                    ProgressView()
                      .controlSize(.mini)
                      .frame(width: 10, height: 10)
                  } else {
                    Image(systemName: "arrow.clockwise")
                  }
                  Text("Regenerate")
                }
                .font(.caption)
              }
              .buttonStyle(.bordered)
              .disabled(isRegenerating)
            }

            HStack(alignment: .top) {
              Text("Topics")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

              HStack(spacing: 6) {
                ForEach(meta.topics, id: \.self) { topic in
                  Text(topic)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
                }
              }
            }

            metadataRow(label: "Confidence", value: String(format: "%.2f", meta.confidence))
            metadataRow(label: "Generated", value: formattedDate(meta.generatedAt))
            metadataRow(label: "Strategy", value: meta.strategy)
            metadataRow(label: "Model", value: meta.model)
            metadataRow(label: "Messages", value: "\(meta.messageCount)")
            metadataRow(label: "Latency", value: "\(meta.latencyMs)ms")
          }

          Divider()
        } else {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("AI Summary")
                .font(.headline)
              Spacer()
              ProgressView()
                .controlSize(.mini)
                .frame(width: 10, height: 10)
            }
            Text("Generating metadata…")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Divider()
        }

        // Actions
        VStack(spacing: 8) {
          if !isActive {
            Button {
              onSelect()
            } label: {
              Label("Select for Monitoring", systemImage: "play.circle.fill")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
          }

          Button {
            NSWorkspace.shared.selectFile(session.fileURL.path, inFileViewerRootedAtPath: "")
          } label: {
            Label("Reveal in Finder", systemImage: "folder")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSWorkspace.shared.open(session.fileURL)
          } label: {
            Label("Open in Default Editor", systemImage: "doc.text")
              .frame(maxWidth: .infinity)
          }

          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.fileURL.path, forType: .string)
          } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.bordered)
      }
      .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: session.fileURL) {
      // Load metadata on appearance or when session changes
      await loadMetadata()
    }
  }

  @MainActor
  private func loadMetadata() async {
    let store = SidecarMetadataStore()
    metadata = await store.load(for: session.fileURL)

    // If no cached metadata, trigger generation
    if metadata == nil {
      do {
        metadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(for: session)
      } catch {
        // Failed to generate, metadata stays nil
      }
    }
  }

  @MainActor
  private func regenerateMetadata() async {
    isRegenerating = true
    defer { isRegenerating = false }

    do {
      let newMetadata = try await TranscriptMetadataOrchestrator.shared.ensureMetadata(
        for: session,
        forceRegenerate: true
      )
      metadata = newMetadata

      // Notify parent view to update list
      onMetadataUpdate?(session.fileURL, newMetadata)
    } catch {
      // Failed to regenerate, keep existing metadata
    }
  }

  @ViewBuilder
  private func metadataRow(label: String, value: String) -> some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(width: 100, alignment: .leading)

      Text(value)
        .font(.subheadline)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var providerName: String {
    switch session.provider {
    case .claudeCode: return "Claude Code"
    case .codexCLI: return "Codex CLI"
    case .other: return "Other"
    }
  }

  private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }

  private func fileSize() -> String? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: session.fileURL.path),
          let size = attrs[.size] as? Int64 else {
      return nil
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func lineCount() -> Int? {
    guard let content = try? String(contentsOf: session.fileURL, encoding: .utf8) else {
      return nil
    }
    return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
  }
}

// MARK: - Previews

#if DEBUG
struct TranscriptInventoryView_Previews: PreviewProvider {
  static var previews: some View {
    TranscriptInventoryView { _ in
      // Session selection handler
    }
    .environment(ConversationMonitor.shared)
  }
}
#endif
```

## File: Contextify/Contextify/ConversationSources.swift

```swift
import Foundation

struct TranscriptSession: Hashable, Sendable {
    let provider: TimelineSourceContext.Provider
    let identifier: String
    let fileURL: URL
    let lastActivity: Date
}

protocol ConversationTranscriptProvider: Sendable {
    func sessions(for projectPath: String) -> [TranscriptSession]
    func sessions(for context: ProjectContext) -> [TranscriptSession]
}

extension ConversationTranscriptProvider {
    // Default implementation for backward compatibility
    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        return sessions(for: context.workingDirectory.path)
    }
}

struct ClaudeTranscriptProvider: ConversationTranscriptProvider {
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default
        let projectDirName = projectPath.replacingOccurrences(of: "/", with: "-")
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let projectDir = projectsDir.appendingPathComponent(projectDirName)

        guard fm.fileExists(atPath: projectDir.path) else { return [] }

        do {
            let files = try fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension == "jsonl" }

            return files.compactMap { fileURL in
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let lastMod = values?.contentModificationDate ?? .distantPast
                return TranscriptSession(
                    provider: .claudeCode,
                    identifier: fileURL.lastPathComponent,
                    fileURL: fileURL,
                    lastActivity: lastMod
                )
            }
        } catch {
            return []
        }
    }
}

struct CodexTranscriptProvider: ConversationTranscriptProvider {
    func sessions(for projectPath: String) -> [TranscriptSession] {
        return sessionsForPath(projectPath)
    }

    func sessions(for context: ProjectContext) -> [TranscriptSession] {
        var allSessions: [TranscriptSession] = []

        // Collect sessions from all project paths (working directory, git root, worktrees)
        for projectURL in context.allProjectPaths() {
            allSessions.append(contentsOf: sessionsForPath(projectURL.path))
        }

        // Deduplicate by file URL
        var seen = Set<URL>()
        return allSessions.filter { session in
            seen.insert(session.fileURL).inserted
        }
    }

    private func sessionsForPath(_ projectPath: String) -> [TranscriptSession] {
        let fm = FileManager.default
        let codexSessionsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")

        guard fm.fileExists(atPath: codexSessionsDir.path) else { return [] }

        // Get git repository URL for this path (if available)
        let gitRepoURL = getGitRepositoryURL(for: projectPath)

        // Find all JSONL files in sessions directory (including subdirectories)
        let jsonlFiles = findJSONLFiles(in: codexSessionsDir)

        // Parse each file looking for session_meta with matching cwd or git repo
        return jsonlFiles.compactMap { fileURL in
            parseCodexSession(fileURL, matchingPath: projectPath, gitRepoURL: gitRepoURL)
        }
    }

    private func findJSONLFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var jsonlFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }
        return jsonlFiles
    }

    private func parseCodexSession(_ fileURL: URL, matchingPath: String, gitRepoURL: String?) -> TranscriptSession? {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? fileHandle.close() }

        // Read file line by line looking for session_meta
        guard let data = try? Data(contentsOf: fileURL),
              let contents = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            guard !line.isEmpty,
                  let jsonData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  json["type"] as? String == "session_meta",
                  let payload = json["payload"] as? [String: Any] else {
                continue
            }

            // Check if this session matches our project by cwd or git repo URL
            let sessionCwd = payload["cwd"] as? String
            let sessionGitInfo = payload["git"] as? [String: Any]
            let sessionRepoURL = sessionGitInfo?["repository_url"] as? String

            let isMatch = sessionCwd == matchingPath ||
                          (gitRepoURL != nil && sessionRepoURL == gitRepoURL)

            guard isMatch else { continue }

            // Found a matching session_meta
            let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let lastMod = values?.contentModificationDate ?? .distantPast

            return TranscriptSession(
                provider: .codexCLI,
                identifier: fileURL.lastPathComponent,
                fileURL: fileURL,
                lastActivity: lastMod
            )
        }

        return nil
    }

    private func getGitRepositoryURL(for path: String) -> String? {
        let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
        let configFile = gitDir.appendingPathComponent("config")

        guard let configData = try? String(contentsOf: configFile, encoding: .utf8) else {
            return nil
        }

        // Parse git config to find remote origin URL
        let lines = configData.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "[remote \"origin\"]" {
                inOriginSection = true
                continue
            }

            if trimmed.hasPrefix("[") && inOriginSection {
                inOriginSection = false
            }

            if inOriginSection && trimmed.hasPrefix("url = ") {
                return String(trimmed.dropFirst("url = ".count))
            }
        }

        return nil
    }
}

struct ActiveConversationResolver: Sendable {
    private let providers: [any ConversationTranscriptProvider]

    init(providers: [any ConversationTranscriptProvider]) {
        self.providers = providers
    }

    func resolveActiveSession(for projectPath: String) -> TranscriptSession? {
        providers
            .flatMap { $0.sessions(for: projectPath) }
            .max(by: { $0.lastActivity < $1.lastActivity })
    }

    func resolveAllSessions(for context: ProjectContext) -> [TranscriptSession] {
        providers
            .flatMap { $0.sessions(for: context) }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    func resolveActiveSession(for context: ProjectContext) -> TranscriptSession? {
        resolveAllSessions(for: context).first
    }
}
```

## File: Contextify/Contextify/SidecarMetadataStore.swift

```swift
//
//  SidecarMetadataStore.swift
//  Contextify
//
//  Temporary stub for metadata storage during SQL migration
//  TODO: Migrate to SQL backend (see sql-integration-plan-v2.md Part 7)
//

import Foundation
import CryptoKit

/// Temporary in-memory metadata store (no persistence)
/// This stub allows the inventory view to continue working during SQL cutover
actor SidecarMetadataStore {
  private var cache: [URL: TranscriptMetadata] = [:]

  func load(for url: URL) -> TranscriptMetadata? {
    return cache[url]
  }

  func save(_ metadata: TranscriptMetadata, for url: URL) {
    cache[url] = metadata
  }

  func isFresh(
    _ metadata: TranscriptMetadata,
    for url: URL,
    promptVersion: Int,
    generatorVersion: Int
  ) -> Bool {
    // Check if versions match
    guard metadata.promptVersion == promptVersion,
          metadata.generatorVersion == generatorVersion else {
      return false
    }

    // Check if file has been modified since metadata was generated
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let modDate = attrs[.modificationDate] as? Date else {
      return false
    }

    let metaDate = metadata.generatedAt
    return modDate <= metaDate
  }

  func sha256(url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
  }

  func flushHeuristicMetadata(for url: URL, exchanges: [Exchange]) {
    // Stub: generate simple heuristic metadata
    let metadata = HeuristicMetadata.generate(exchanges: exchanges)
    cache[url] = metadata
  }

  // Batch flush for inventory view
  func flushHeuristicMetadata(for sessions: [TranscriptSession]) -> Int {
    var flushed = 0
    for session in sessions {
      // Skip if already has metadata
      if cache[session.fileURL] != nil { continue }

      // Quick parse to get exchanges
      let parser = TranscriptParser()
      guard let exchanges = try? parser.parseExchanges(url: session.fileURL) else { continue }

      // Generate and cache heuristic metadata
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      cache[session.fileURL] = metadata
      flushed += 1
    }
    return flushed
  }
}
```

## File: Contextify/Contextify/TranscriptMetadataOrchestrator.swift

```swift
import Foundation
import OSLog

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Simple async semaphore for controlling concurrent access
actor AsyncSemaphore {
  private let limit: Int
  private var permits: Int

  init(_ limit: Int) {
    self.limit = limit
    self.permits = limit
  }

  func acquire() async {
    while permits == 0 {
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
    }
    permits -= 1
  }

  func release() {
    permits = min(permits + 1, limit)
  }
}

/// Orchestrates transcript metadata generation with caching, retries, and circuit breaking
actor TranscriptMetadataOrchestrator {
  static let shared = TranscriptMetadataOrchestrator()

  private let log = Logger(subsystem: "dev.contextify.metadata", category: "Orchestrator")
  private let store = SidecarMetadataStore()
  private let parser = TranscriptParser()
  private let builder = ContextBuilder()
  private let llm: TranscriptMetadataLLM
  private let postProcessor = MetadataPostProcessor()

  private init() {
    self.llm = TranscriptMetadataLLM.shared
  }

  private let currentPromptVersion = 2
  private let currentGeneratorVersion = 1

  // Circuit breaker state with sliding window
  private var requestWindow: [Date] = []
  private var failureCount = 0
  private let windowSpan: TimeInterval = 300 // 5 minutes
  private let circuitBreakerThreshold = 5

  // Concurrency control
  private var activeTasks: [URL: Task<TranscriptMetadata, Error>] = [:]
  private let llmGate = AsyncSemaphore(2)

  // MARK: - Public API

  /// Ensures metadata exists for a session, generating if needed
  func ensureMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool = false
  ) async throws -> TranscriptMetadata {
    // Cancel existing task if forcing regeneration
    if forceRegenerate, let existingTask = activeTasks[session.fileURL] {
      existingTask.cancel()
      activeTasks.removeValue(forKey: session.fileURL)
    }

    // Check for existing task
    if let existingTask = activeTasks[session.fileURL] {
      log.info("Reusing existing generation task for \(session.identifier, privacy: .public)")
      return try await existingTask.value
    }

    // Create new task
    let task = Task<TranscriptMetadata, Error> {
      defer {
        Task { self.removeTask(for: session.fileURL) }
      }
      return try await self.generateMetadata(for: session, forceRegenerate: forceRegenerate)
    }

    activeTasks[session.fileURL] = task
    return try await task.value
  }

  // MARK: - Private Implementation

  private func removeTask(for url: URL) {
    activeTasks.removeValue(forKey: url)
  }

  private func generateMetadata(
    for session: TranscriptSession,
    forceRegenerate: Bool
  ) async throws -> TranscriptMetadata {
    let startTime = Date()

    // Check cache unless forcing regeneration
    if !forceRegenerate,
       let cached = await store.load(for: session.fileURL),
       await store.isFresh(
        cached,
        for: session.fileURL,
        promptVersion: currentPromptVersion,
        generatorVersion: currentGeneratorVersion
       ) {
      log.info("Using cached metadata for \(session.identifier, privacy: .public)")
      return cached
    }

    log.info("Generating metadata for \(session.identifier, privacy: .public)")

    // Parse exchanges (background-safe, no MainActor needed)
    let parseStart = Date()
    let exchanges = try parser.parseExchanges(url: session.fileURL)
    let parseTime = Date().timeIntervalSince(parseStart)

    // Handle very short transcripts with heuristic
    if exchanges.count < 3 {
      log.info("Very short transcript (\(exchanges.count) exchanges), using heuristic")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      await store.save(metadata, for: session.fileURL)
      return metadata
    }

    // Check circuit breaker
    if shouldUseCircuitBreaker() {
      log.warning("Circuit breaker active, using heuristic fallback")
      let metadata = HeuristicMetadata.generate(exchanges: exchanges)
      await store.save(metadata, for: session.fileURL)
      return metadata
    }

    // Calculate available token budget using actual LLM tokenizer
    #if canImport(FoundationModels)
    let availableTokens: Int
    if #available(macOS 26, *) {
      // For adaptive strategy, we need to know the budget first
      // Use a preliminary count estimate to decide strategy
      let preliminaryCount = exchanges.count
      availableTokens = await llm.calculateAvailableContextTokens(
        sampledCount: min(preliminaryCount, MetadataBudgets.bookendCount * 2),
        totalCount: preliminaryCount
      )
    } else {
      // Fallback to static budget if LLM not available
      availableTokens = MetadataBudgets.samplerBudget
    }
    #else
    let availableTokens = MetadataBudgets.samplerBudget
    #endif

    // Select strategy based on available budget and exchange count
    let strategy: GenerationStrategy
    if exchanges.count <= MetadataBudgets.fullStrategyLimit {
      strategy = .full
    } else {
      strategy = .adaptive
    }

    // Build context with dynamic budget (background-safe, no MainActor needed)
    let samplingStart = Date()
    let context = try builder.build(
      exchanges: exchanges,
      strategy: strategy,
      budgetTokens: availableTokens
    )
    let samplingTime = Date().timeIntervalSince(samplingStart)

    // Log context size for debugging
    log.info("Built context: \(context.text.count) chars, estimated \(context.text.count / 4) tokens, budget was \(availableTokens) tokens")

    // Call LLM (with fallback to bookends on failure)
    var metadata: TranscriptMetadata
    let llmStart = Date()

    do {
      // Wait for LLM slot
      await llmGate.acquire()
      defer { Task { await llmGate.release() } }

      #if canImport(FoundationModels)
      if #available(macOS 26, *) {
        let guided = try await llm.singlePass(
          context: context.text,
          sampledCount: context.sampledCount,
          totalCount: exchanges.count
        )

        // Post-process (background-safe)
        metadata = postProcessor.apply(to: guided, context: context.text)
        metadata.messageCount = exchanges.count
        metadata.strategy = "singlePass:\(strategy.rawValue)"

        recordSuccess()
      } else {
        throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
      }
      #else
      throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
      #endif
    } catch {
      log.error("LLM call failed: \(error.localizedDescription, privacy: .public)")
      recordFailure()

      // Try bookends fallback if we weren't already using it
      if strategy != .bookends {
        log.info("Retrying with bookends strategy...")
        let bookendContext = try builder.build(
          exchanges: exchanges,
          strategy: .bookends,
          budgetTokens: availableTokens
        )

        do {
          await llmGate.acquire()
          defer { Task { await llmGate.release() } }

          #if canImport(FoundationModels)
          if #available(macOS 26, *) {
            let guided = try await llm.singlePass(
              context: bookendContext.text,
              sampledCount: bookendContext.sampledCount,
              totalCount: exchanges.count
            )

            metadata = postProcessor.apply(to: guided, context: bookendContext.text)
            metadata.messageCount = exchanges.count
            metadata.strategy = "singlePass:bookends-fallback"

            recordSuccess()
          } else {
            throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
          }
          #else
          throw TranscriptMetadataLLM.LLMError.unexpectedEnvironment
          #endif
        } catch {
          log.error("Bookends fallback also failed, using heuristic")
          recordFailure()
          metadata = HeuristicMetadata.generate(exchanges: exchanges)
          metadata.strategy = "heuristic-after-failure"
        }
      } else {
        // Already tried bookends, use heuristic
        metadata = HeuristicMetadata.generate(exchanges: exchanges)
        metadata.strategy = "heuristic-after-failure"
      }
    }

    let llmTime = Date().timeIntervalSince(llmStart)

    // Finalize metadata
    let storageStart = Date()
    metadata.transcriptSHA256 = try await store.sha256(url: session.fileURL)
    metadata.promptVersion = currentPromptVersion
    metadata.generatorVersion = currentGeneratorVersion
    let totalTime = Date().timeIntervalSince(startTime)
    metadata.latencyMs = Int(totalTime * 1000)

    // Save to sidecar
    await store.save(metadata, for: session.fileURL)
    let storageTime = Date().timeIntervalSince(storageStart)

    // Log metrics
    let metrics = GenerationMetrics(
      parseTimeMs: Int(parseTime * 1000),
      samplingTimeMs: Int(samplingTime * 1000),
      llmTimeMs: Int(llmTime * 1000),
      storageTimeMs: Int(storageTime * 1000),
      totalTimeMs: Int(totalTime * 1000),
      exchangeCount: exchanges.count,
      strategy: strategy,
      success: !metadata.needsReview,
      needsReview: metadata.needsReview
    )

    logMetrics(metrics, for: session.identifier)

    return metadata
  }

  // MARK: - Circuit Breaker

  private func shouldUseCircuitBreaker() -> Bool {
    let now = Date()
    // Clean up old entries outside the window
    requestWindow = requestWindow.filter { now.timeIntervalSince($0) <= windowSpan }

    let total = max(1, requestWindow.count)
    let ratio = Double(failureCount) / Double(total)

    // Open circuit if failure ratio >= 60% and we have at least 5 requests
    return ratio >= 0.6 && total >= 5
  }

  private func recordSuccess() {
    let now = Date()
    requestWindow.append(now)
    requestWindow = requestWindow.filter { now.timeIntervalSince($0) <= windowSpan }
    // Decay failure count on success, but don't reset completely
    failureCount = max(0, failureCount - 1)
  }

  private func recordFailure() {
    let now = Date()
    requestWindow.append(now)
    requestWindow = requestWindow.filter { now.timeIntervalSince($0) <= windowSpan }
    failureCount += 1

    let total = max(1, requestWindow.count)
    let ratio = Double(failureCount) / Double(total)
    if ratio >= 0.6 && total >= 5 {
      log.warning("Circuit breaker triggered: \(self.failureCount) failures out of \(total) requests (\(String(format: "%.1f%%", ratio * 100)))")
    }
  }

  // MARK: - Metrics Logging

  private func logMetrics(_ metrics: GenerationMetrics, for identifier: String) {
    log.info("""
      Metadata generated for \(identifier, privacy: .public): \
      parse=\(metrics.parseTimeMs)ms, \
      sampling=\(metrics.samplingTimeMs)ms, \
      llm=\(metrics.llmTimeMs)ms, \
      storage=\(metrics.storageTimeMs)ms, \
      total=\(metrics.totalTimeMs)ms, \
      exchanges=\(metrics.exchangeCount), \
      strategy=\(metrics.strategy.rawValue, privacy: .public), \
      needsReview=\(metrics.needsReview)
      """)
  }
}
```

## File: Contextify/Contextify/TranscriptInventoryWindow.swift

```swift
import SwiftUI
import ContextifyCore

/// Window-specific container for TranscriptInventoryView
/// Provides window-appropriate toolbar and data binding
@MainActor
struct TranscriptInventoryWindow: View {
  @Environment(ConversationMonitor.self) private var monitor

  var body: some View {
    TranscriptInventoryView { session in
      Task { @MainActor in
        await monitor.switchToSessionFromUser(session)
      }
    }
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          Task { @MainActor in
            await monitor.refresh()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
      }
    }
    .task {
      // Load sessions from database when window appears
      await monitor.loadAllSessionsFromDatabase()
    }
  }
}
```

## File: Contextify/Contextify/ConversationMonitor.swift (Key Sections)

```swift

// startMonitoring() - Initializes TranscriptOrchestrator and creates project
@MainActor
func startMonitoring() {
    Task { @MainActor [weak self] in
        guard let self else { return }

        // 1. Get project from HUD
        guard let projectRoot = HUDViewModel.shared.projectRootURL else {
            self.lastError = "No project root set"
            return
        }

        // 2. Initialize shared orchestrator
        self.orchestrator = try TranscriptOrchestrator(dbManager: .shared)

        // 3. Create project (CRITICAL: wait for DB commit)
        self.currentProjectId = try self.orchestrator.getOrCreateProject(
            name: projectRoot.lastPathComponent,
            rootPath: projectRoot.path
        )

        // 4. Start background discovery loop
        self.backgroundTasks = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? await self?.discoverNewTranscripts(projectId: projectId, orchestrator: orchestrator)
                }
            }
        }

        // 5. Load initial feed from SQL
        await self.loadFeedFromSQL()
    }
}

// discoverNewTranscripts() - Background task that persists discovered transcripts to DB
nonisolated private func discoverNewTranscripts(projectId: String, orchestrator: TranscriptOrchestrator) async throws {
    // Find JSONL files on disk
    let claudeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects/\(projectDirName)")

    let filesOnDisk = try FileManager.default.contentsOfDirectory(at: claudeDir, ...)
        .filter { $0.pathExtension == "jsonl" }

    // For each file, persist to database
    for fileURL in filesOnDisk {
        try orchestrator.discoverTranscript(
            projectId: projectId,
            fileURL: fileURL,
            provider: "claude.code",
            providerSessionId: fileURL.lastPathComponent,
            startWatching: true  // ✅ PERSISTS TO DB + starts file watcher
        )
    }
}

// loadFeedFromSQL() - Query entries with LEFT JOIN on cache
private func loadFeedFromSQL() async {
    guard let projectId = currentProjectId, orchestrator != nil else { return }

    // Single query gets entries + cache
    let feed = try orchestrator.getRecentFeed(
        forProject: projectId,
        limit: config.maxEntries,
        generatorSignature: generatorSignature()
    )

    // Map to UI entries and collect cache misses
    var misses: [CacheMiss] = []
    let newEntries = feed.map { entry, cache in
        if cache == nil {
            misses.append(CacheMiss(from: entry))
        }
        return toTimelineEntry(entry, cached: cache)
    }

    setEntries(newEntries)

    // Queue cache misses for background LLM generation
    if !misses.isEmpty, let generator = cacheMissGenerator {
        Task { await generator.queueMisses(misses) }
    }
}

// loadAllSessionsFromDatabase() - Called by TranscriptInventoryWindow
@MainActor
func loadAllSessionsFromDatabase() async {
    guard let projectId = currentProjectId, orchestrator != nil else {
        log.warning("Cannot load sessions: no project or orchestrator")
        return
    }

    do {
        let transcripts = try orchestrator.getTranscripts(forProject: projectId)
        let latestTimestamps = try orchestrator.latestTimestampsByTranscript(projectId: projectId)
        let sessions = Self.mapTranscriptsToSessions(transcripts: transcripts, latestTimestamps: latestTimestamps)

        allSessions = sessions
        log.info("Loaded \(sessions.count) sessions from database for transcript inventory")
    } catch {
        log.error("Failed to load sessions from database: \(error.localizedDescription, privacy: .public)")
    }
}

// mapTranscriptsToSessions() - Convert DB transcripts to TranscriptSession objects
nonisolated private static func mapTranscriptsToSessions(transcripts: [Transcript], latestTimestamps: [String: Int]) -> [TranscriptSession] {
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

        return TranscriptSession(
            provider: provider,
            identifier: transcript.id,
            fileURL: fileURL,
            lastActivity: lastActivity
        )
    }.sorted { $0.lastActivity > $1.lastActivity }
}
```

## Pertinent Log Entries from `/tmp/contextify-02.log`

```
error 15:53:28.254329-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.296843-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.345612-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.402157-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.450933-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.507249-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.563195-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.621806-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.679124-0700 Contextify Circuit breaker active, using heuristic fallback
error 15:53:28.738917-0700 Contextify Circuit breaker active, using heuristic fallback
```

**Analysis**: Repeated circuit breaker errors indicate TranscriptMetadataOrchestrator's failure threshold was exceeded. Without SQL cache, every transcript triggers fresh LLM call. When failures accumulate (60% failure rate over 5+ requests), circuit breaker opens and all subsequent calls use heuristic fallback.

**Expected After Fix**: Logs should show "Using cached metadata for {session}" instead of circuit breaker errors. LLM calls only happen once per transcript, with results persisted to SQL.

---

**End of File Appendix**
