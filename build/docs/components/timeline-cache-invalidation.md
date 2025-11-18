# Timeline Cache Invalidation Strategy

**Status:** Active (2025-11-17)
**Related:** `build/docs/components/timeline-cache.md`, `TimelineCacheMissGenerator.swift`
**Purpose:** Deep implementation guide for cache invalidation, generator versioning, and migration strategies

---

## Executive Summary

This document provides implementation-level details for **timeline cache invalidation** beyond the cache architecture overview. Read this when:
- Planning LLM prompt changes or model upgrades
- Debugging stale cache issues
- Understanding cache miss triggers
- Implementing cache management features
- Investigating user-edited entry preservation

**Related Cache Doc:** `build/docs/components/timeline-cache.md` - Read that first for cache architecture and LLM integration.

---

## Cache Schema Architecture

### Timeline Cache Table

```sql
-- DatabaseSchema.swift:730-748
CREATE TABLE IF NOT EXISTS timeline_cache (
    content_sha256 TEXT NOT NULL,       -- SHA256 of entry content
    window_sha256 TEXT NOT NULL,        -- SHA256 of [prev2_id, prev1_id]
    entry_id TEXT NOT NULL              -- Reference to transcript_entries(id)
        REFERENCES transcript_entries(id) ON DELETE CASCADE,
    generator_signature TEXT NOT NULL,  -- Prompt version identifier
    disposition TEXT NOT NULL,          -- "proposes", "implements", "asks", etc.
    present_form TEXT NOT NULL,         -- "Claude proposes to..."
    past_form TEXT NOT NULL,            -- "Claude proposed to..."
    selected_form TEXT NOT NULL         -- "present" or "past"
        CHECK (selected_form IN ('present','past')),
    verb_lemma TEXT,                    -- Base verb ("propose", "implement")
    generated_at INTEGER NOT NULL,      -- Unix timestamp
    user_edited INTEGER NOT NULL DEFAULT 0,  -- 1 if manually edited
    user_text TEXT,                     -- Custom text from user
    edited_at INTEGER,                  -- Unix timestamp of edit
    request_id TEXT,                    -- LLM request ID (tracing)
    duration REAL,                      -- Generation latency (seconds)
    PRIMARY KEY (content_sha256, window_sha256)
) WITHOUT ROWID
```

**Key Design Decisions:**

1. **Composite Primary Key:** `(content_sha256, window_sha256)`
   - Same content + different context → different cache entry
   - Hash-based deduplication prevents duplicate LLM calls

2. **WITHOUT ROWID:**
   - Optimizes for hash-based lookups (no extra ROWID column)
   - Cache queries are always by composite key

3. **generator_signature:**
   - **Not part of primary key** (intentional!)
   - Allows cache misses when prompt changes without deleting old entries
   - Old entries remain until regenerated

4. **No TTL or expiry columns:**
   - Cache entries **never expire** automatically
   - Manual deletion or regeneration only

5. **user_edited flag:**
   - Protects manual edits from automatic regeneration
   - Unimplemented in current UI (no user editing feature yet)

---

## Cache Miss Triggers

### Trigger 1: New Content

**When:** Entry with `content_sha256` never seen before.

**Example:**
```
Entry: "Implement dark mode"
content_sha256: abc123...
window_sha256: def456...

Query: SELECT * FROM timeline_cache WHERE content_sha256 = 'abc123...' AND window_sha256 = 'def456...'
Result: NULL → CACHE MISS
```

**Consequence:** `TimelineCacheMissGenerator` queues entry for LLM generation.

### Trigger 2: Context Change (Window Hash)

**When:** Same content, different preceding entries.

**Example:**
```
Entry A: "Fix the bug"
  prev1 = "User asked about performance"
  window_sha256 = hash([null, "performance-entry-id"])
  → Summary: "Claude proposes to fix the performance bug"

Entry B: "Fix the bug"  (SAME CONTENT)
  prev1 = "User reported a crash"
  window_sha256 = hash([null, "crash-entry-id"])  ← DIFFERENT HASH
  → Summary: "Claude proposes to fix the crash"
```

**Why Cache Miss?**
- Composite key `(content_sha256, window_sha256)` doesn't match
- LLM needs different context for accurate summary

**Performance Impact:** Window changes are common (conversations progress) → frequent misses are expected.

### Trigger 3: Generator Signature Change

**When:** Prompt version bumped, but old cache entries still exist.

**Current Query Pattern:**

```sql
-- timeline-cache.md:131-143
SELECT
    e.*,
    c.present_form, c.past_form, c.disposition
FROM transcript_entries e
LEFT JOIN timeline_cache c
    ON c.content_sha256 = e.content_sha256
    AND c.window_sha256 = e.window_sha256
    AND c.generator_signature = ?  ← CRITICAL: Filters by signature
WHERE e.project_id = ?
    AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC
LIMIT 50
```

**Example Scenario:**

```
Initial state (generator_signature = "v1.0"):
  content_sha256 = abc123
  window_sha256 = def456
  generator_signature = "v1.0"
  present_form = "Claude suggested to..."

Prompt updated (generator_signature = "v2.0"):
  Query: ... AND c.generator_signature = 'v2.0'
  Result: NULL → CACHE MISS (even though abc123+def456 exists!)

LLM regenerates with new prompt:
  INSERT INTO timeline_cache VALUES (
    content_sha256 = abc123,
    window_sha256 = def456,
    generator_signature = "v2.0",  ← NEW VERSION
    present_form = "Claude proposes to..."  ← DIFFERENT PHRASING
  )
```

**Important:** Old v1.0 entry remains in database but is **never queried** again (signature filter prevents it).

---

## Generator Signature Versioning

### What Is generator_signature?

**Definition:** A string identifier that changes when:
- LLM prompt template is modified
- Model is upgraded (e.g., Intelligence 1.0 → Intelligence 2.0)
- Summarization algorithm is changed

**Format:** Currently unspecified (implementation-dependent). Suggested: `"prompt-v2.0"` or `"intelligence-2.0"`.

### When to Bump Generator Signature

**Bump When:**
1. **Prompt template changes:**
   ```swift
   // OLD
   let prompt = "Generate JSON: { \"present\": \"...\", \"past\": \"...\" }"

   // NEW (more specific instructions)
   let prompt = "Generate JSON with technical verb forms: { \"present\": \"...\", \"past\": \"...\" }"
   // → Bump signature to "v2.0"
   ```

2. **Model upgrade:**
   ```swift
   // OLD: FoundationLLM uses Intelligence 1.0
   generator_signature = "intelligence-1.0"

   // NEW: macOS update provides Intelligence 2.0
   generator_signature = "intelligence-2.0"
   // → All entries regenerated with new model
   ```

3. **Disposition taxonomy changes:**
   ```swift
   // OLD: disposition = "proposes" or "implements"
   // NEW: disposition = "proposes", "implements", "questions", "clarifies", "refactors"
   // → Bump signature to regenerate with expanded taxonomy
   ```

**Don't Bump When:**
- Bug fixes in cache storage logic (doesn't affect LLM output)
- UI changes (presentation layer, not generation layer)
- Performance optimizations (batch size, rate limiting)

### Migration Procedure

**Step 1: Update signature constant**

```swift
// FoundationLLM.swift (hypothetical)
struct GeneratorConfig {
    static let signature = "prompt-v2.0"  // ← Update this
}
```

**Step 2: Deploy app update**

Users download new version with new signature.

**Step 3: Observe cache misses**

On next timeline load:
- All entries match old signature ("v1.0")
- Query filters by new signature ("v2.0")
- Result: 100% cache miss rate

**Step 4: Background regeneration**

`TimelineCacheMissGenerator` queues all entries:
- ~50 entries visible in timeline
- Processes at ~1 entry/second (FoundationLLM limitation)
- Complete regeneration in ~1 minute for typical timeline

**Step 5: Old entries remain (tombstones)**

Old cache entries are **never deleted** (no cleanup job). They just sit in database until:
- Entry is deleted (CASCADE delete)
- Manual database cleanup
- User uninstalls app

**Impact:**
- Database bloat: ~500 bytes/entry × duplicate entries
- 1000 entries with 2 versions = 1MB extra (negligible)

---

## Cache Eviction Strategies

### Current Strategy: Never Evict

**Policy:** Cache entries are **never** automatically evicted.

**Rationale:**
- Disk space is cheap (~500 bytes/entry)
- LLM generation is expensive (~500ms-2s/entry)
- Cache hits are valuable (instant display)

**Growth Rate:**

Assuming:
- 10 entries/day created
- ~365 days/year
- Average 2 generator versions over app lifetime

Total entries: `10 × 365 × 2 = 7,300 entries`
Total size: `7,300 × 500 bytes ≈ 3.6MB`

**Trade-off:** Disk space vs re-generation cost → **disk space wins**.

### Future Strategy: Time-Based Expiry (Unimplemented)

**Proposal:** Add `expires_at` column to `timeline_cache`:

```sql
ALTER TABLE timeline_cache ADD COLUMN expires_at INTEGER;  -- Unix timestamp

-- Cleanup query (run daily)
DELETE FROM timeline_cache
WHERE expires_at < ?  -- Current time
  AND user_edited = 0  -- Don't delete user edits!
```

**Expiry Policy:**
- Cache entries expire after 90 days (configurable)
- User-edited entries **never** expire (`user_edited = 1`)
- Expired entries → cache miss → regenerate on next load

**Implementation Blockers:**
- No expiry requirement yet (disk space not an issue)
- Adds complexity (cron job, expiry management)

---

## Content+Window Hash Changes

### How Hashes Are Computed

**Content Hash:**

```swift
// Hypothetical implementation
func contentSha256(for entry: TranscriptEntry) -> String {
    let data = entry.content.data(using: .utf8)!
    let hash = SHA256.hash(data: data)
    return hash.hexString
}
```

**Window Hash:**

```swift
// Hypothetical implementation
func windowSha256(prev2: String?, prev1: String?) -> String {
    let window = "\(prev2 ?? "null")|\(prev1 ?? "null")"
    let data = window.data(using: .utf8)!
    let hash = SHA256.hash(data: data)
    return hash.hexString
}
```

**Properties:**
- **Deterministic:** Same input → same hash
- **Collision-resistant:** Different input → different hash (probability: 2^-256)
- **Stable:** Hashes never change unless content/window changes

### When Hashes Change

**Content Hash Changes:**
1. **Entry content edited** (user modifies transcript file)
2. **Re-ingestion with different parsing** (unlikely)

**Window Hash Changes:**
1. **Preceding entries change order** (entries inserted/deleted)
2. **Preceding entry IDs change** (rare - entry IDs are stable)
3. **Window size changes** (e.g., prev1+prev2 → prev1+prev2+prev3)

**Consequence:** Hash change → cache miss → regenerate.

---

## User-Edited Entries

### Preservation Strategy

**Schema:**

```sql
user_edited INTEGER NOT NULL DEFAULT 0,  -- Boolean flag
user_text TEXT,                          -- Custom text from user
edited_at INTEGER                        -- Unix timestamp
```

**Update Query:**

```sql
UPDATE timeline_cache
SET user_edited = 1,
    user_text = ?,      -- User's custom summary
    edited_at = ?       -- Current timestamp
WHERE content_sha256 = ?
  AND window_sha256 = ?
```

**Regeneration Filter:**

```swift
// Hypothetical: Skip user-edited entries during regeneration
func regenerateAll() async {
    let misses = await detectMisses()
    let nonEdited = misses.filter { miss in
        // Check if entry was manually edited
        let cache = try? getCachedTimeline(
            contentSha256: miss.contentSha256,
            windowSha256: miss.windowSha256
        )
        return cache?.user_edited != 1
    }

    await generator.queueMisses(nonEdited)
}
```

**Use Cases:**
- User corrects LLM mistake ("proposes" → "implements")
- User prefers custom wording ("suggests" → "recommends")
- User simplifies verbose summary

**Unimplemented:** No UI for editing summaries yet (future feature).

---

## Cache Management Operations

### Operation 1: Full Regeneration

**Scenario:** Prompt updated, need to regenerate all entries for current project.

**SQL:**

```sql
-- Delete all cache entries for old generator signature
DELETE FROM timeline_cache
WHERE generator_signature != 'v2.0'  -- Old versions
  AND entry_id IN (
    SELECT id FROM transcript_entries WHERE project_id = ?
  );
```

**Consequence:** Next timeline load → 100% cache miss → background regeneration.

### Operation 2: Selective Regeneration

**Scenario:** Fix bad summaries for specific disposition (e.g., all "proposes" entries).

**SQL:**

```sql
-- Delete cache entries with specific disposition
DELETE FROM timeline_cache
WHERE disposition = 'proposes'
  AND user_edited = 0  -- Preserve user edits
  AND entry_id IN (
    SELECT id FROM transcript_entries WHERE project_id = ?
  );
```

### Operation 3: Purge Old Versions

**Scenario:** Clean up tombstone entries from previous generator versions.

**SQL:**

```sql
-- Delete cache entries for obsolete signatures
DELETE FROM timeline_cache
WHERE generator_signature IN ('v1.0', 'v1.1')  -- Old versions only
  AND user_edited = 0;  -- Preserve user edits

-- Vacuum to reclaim disk space
VACUUM;
```

**Impact:**
- Reclaims ~500 bytes per deleted entry
- No effect on current timeline (uses v2.0 signature)

### Operation 4: Entry-Specific Regeneration

**Scenario:** User reports bad summary for specific entry, wants to re-roll.

**SQL:**

```sql
-- Delete cache entry for specific entry
DELETE FROM timeline_cache
WHERE entry_id = ?;  -- Specific entry ID

-- Next timeline load will regenerate
```

**Future UI:** "Regenerate Summary" button in entry context menu.

---

## Prompt Change Migration Path

### Example: Disposition Taxonomy Expansion

**Old Prompt (v1.0):**
```
Generate JSON:
{
  "present": "...",
  "past": "...",
  "disposition": "proposes" | "implements"
}
```

**New Prompt (v2.0):**
```
Generate JSON:
{
  "present": "...",
  "past": "...",
  "disposition": "proposes" | "implements" | "questions" | "clarifies" | "refactors" | "debugs"
}
```

**Migration Steps:**

1. **Update prompt template in `FoundationLLM.swift`:**
   ```swift
   let prompt = """
       Content: \(content)
       Context: \(context)

       Generate JSON with disposition from:
       ["proposes", "implements", "questions", "clarifies", "refactors", "debugs"]

       {
         "present": "...",
         "past": "...",
         "disposition": "..."
       }
       """
   ```

2. **Bump generator signature:**
   ```swift
   struct GeneratorConfig {
       static let signature = "prompt-v2.0-taxonomy-expanded"
   }
   ```

3. **Update database schema (if needed):**
   ```sql
   -- Add CHECK constraint for new dispositions
   ALTER TABLE timeline_cache DROP CONSTRAINT IF EXISTS check_disposition;
   ALTER TABLE timeline_cache ADD CONSTRAINT check_disposition
       CHECK (disposition IN (
           'proposes', 'implements', 'questions', 'clarifies',
           'refactors', 'debugs', 'asks', 'directive', 'affirmative', 'negative'
       ));
   ```

4. **Deploy app update**

5. **Observe regeneration:**
   - Users open timeline → all entries miss (signature changed)
   - ~50 entries regenerated in ~1 minute
   - New dispositions appear ("questions", "clarifies", etc.)

6. **Validate:**
   ```sql
   -- Check distribution of new dispositions
   SELECT disposition, COUNT(*) FROM timeline_cache
   WHERE generator_signature = 'prompt-v2.0-taxonomy-expanded'
   GROUP BY disposition;
   ```

---

## Performance Implications

### Cache Miss Rate

**Ideal:** <5% (95% hit rate)
- Timeline load shows cached entries instantly
- Background regeneration handles 5% misses

**After Prompt Update:** 100% (0% hit rate)
- First load after update → all misses
- ~50-100 entries queued
- Regeneration completes in 1-2 minutes
- Subsequent loads → 95%+ hit rate

**Viewport Pruning (Optimization):**

```swift
// TimelineCacheMissGenerator.swift:123-150
func pruneQueue(keepOnly visibleIDs: Set<String>) async {
    // Remove entries not in viewport
    let beforeCount = pendingMisses.count
    pendingMisses.removeAll { miss in
        !visibleIDs.contains(miss.entryId) && miss.entryId != activeEntryID
    }
    let prunedCount = beforeCount - pendingMisses.count
    log.info("[PRUNE] Removed \(prunedCount) entries no longer visible")
}
```

**Impact:**
- User scrolls down → old entries pruned from queue
- Only visible entries regenerated (saves LLM calls)
- Scroll back up → cache miss again (acceptable UX trade-off)

### Database Query Performance

**Timeline Load Query:**

```sql
SELECT e.*, c.present_form, c.past_form, c.disposition
FROM transcript_entries e
LEFT JOIN timeline_cache c
    ON c.content_sha256 = e.content_sha256
    AND c.window_sha256 = e.window_sha256
    AND c.generator_signature = 'v2.0'
WHERE e.project_id = ?
  AND e.display_in_timeline = 1
ORDER BY e.timestamp DESC
LIMIT 50
```

**Index Coverage:**
```sql
-- Covering index for feed queries
CREATE INDEX idx_entries_feed_cover ON transcript_entries (
    project_id, display_in_timeline, timestamp DESC
)

-- Hash-based lookup for cache
CREATE INDEX idx_cache_entry_window ON timeline_cache (
    entry_id, window_sha256
)
```

**Performance:** <5ms for 50-entry timeline (measured on Intel Mac, SQLite WAL mode).

---

## Testing Strategies

### Unit Testing: Cache Miss Detection

```swift
func testCacheMissDetection() async throws {
    let entry = TranscriptEntry(
        id: "test-1",
        content: "Fix the bug",
        contentSha256: "abc123",
        windowSha256: "def456",
        ...
    )

    // No cache entry exists → should be cache miss
    let cache = try? orchestrator.getCachedTimeline(
        contentSha256: "abc123",
        windowSha256: "def456"
    )

    XCTAssertNil(cache)  // Cache miss confirmed
}
```

### Integration Testing: Generator Signature Change

```swift
func testGeneratorSignatureInvalidatesCache() async throws {
    let entry = createTestEntry()

    // Save cache with old signature
    try orchestrator.saveCachedTimeline(TimelineCache(
        contentSha256: entry.contentSha256,
        windowSha256: entry.windowSha256,
        generatorSignature: "v1.0",
        ...
    ))

    // Query with new signature
    let cache = try? orchestrator.getCachedTimeline(
        contentSha256: entry.contentSha256,
        windowSha256: entry.windowSha256,
        generatorSignature: "v2.0"  // ← Different signature
    )

    XCTAssertNil(cache)  // Should be cache miss
}
```

### Manual Testing: Full Regeneration

**Procedure:**

1. **Delete cache entries:**
   ```sql
   DELETE FROM timeline_cache WHERE generator_signature = 'v1.0';
   ```

2. **Reload timeline:**
   ```bash
   # Restart app
   open .derived/Build/Products/Debug/Contextify.app
   ```

3. **Monitor regeneration:**
   ```bash
   log stream --predicate 'subsystem == "dev.contextify.timeline" AND category == "CacheMissGenerator"' \
     | grep "processing\|generated"
   ```

4. **Verify completion:**
   ```sql
   SELECT COUNT(*) FROM timeline_cache WHERE generator_signature = 'v2.0';
   -- Should match visible entry count (~50)
   ```

---

## Debugging Workflows

### Scenario: Stale Cache After Prompt Update

**Symptoms:**
- Old summaries still displayed after prompt change
- Expected new phrasing not appearing

**Debug Steps:**

1. **Check generator signature in query:**
   ```sql
   SELECT DISTINCT generator_signature FROM timeline_cache;
   -- Should show both old and new versions
   ```

2. **Check query parameter:**
   ```swift
   // In code: Ensure using new signature
   let cache = try orchestrator.getCachedTimeline(
       contentSha256: entry.contentSha256,
       windowSha256: entry.windowSha256,
       generatorSignature: "v2.0"  // ← Verify this matches new version
   )
   ```

3. **Force regeneration:**
   ```sql
   DELETE FROM timeline_cache WHERE generator_signature != 'v2.0';
   ```

### Scenario: User Edit Overwritten

**Symptoms:**
- User manually edited summary
- Summary reverted to LLM-generated version

**Debug Steps:**

1. **Check user_edited flag:**
   ```sql
   SELECT user_edited, user_text FROM timeline_cache
   WHERE entry_id = ?;
   ```

2. **Verify regeneration filter:**
   ```swift
   // Should skip user-edited entries
   func regenerate() {
       let misses = detectMisses()
       let filtered = misses.filter { $0.userEdited == false }
       generator.queueMisses(filtered)
   }
   ```

### Scenario: Cache Misses Despite Existing Entry

**Symptoms:**
- Cache entry exists in database
- Query returns NULL (cache miss)

**Debug Steps:**

1. **Check composite key match:**
   ```sql
   SELECT * FROM timeline_cache
   WHERE content_sha256 = ? AND window_sha256 = ?;
   -- Should return entry if hashes match
   ```

2. **Check generator signature:**
   ```sql
   SELECT generator_signature FROM timeline_cache
   WHERE content_sha256 = ? AND window_sha256 = ?;
   -- If old signature, query with new signature will miss
   ```

3. **Verify hash computation:**
   ```swift
   // In code: Log actual hashes
   print("content_sha256: \(entry.contentSha256)")
   print("window_sha256: \(entry.windowSha256)")
   // Compare with database values
   ```

---

## Related Documentation

- **Cache Architecture:** `build/docs/components/timeline-cache.md`
- **Source (Generator):** `Contextify/Contextify/TimelineCacheMissGenerator.swift`
- **Source (LLM):** `Contextify/Contextify/FoundationLLM.swift`
- **Database Schema:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift` (lines 730-748)
- **SQL Backend:** `build/docs/architecture/sql-backend.md`

---

## Changelog

**2025-11-17:**
- Initial invalidation guide created
- Documents cache miss triggers (content, window, generator signature)
- Generator signature versioning strategy
- Migration procedures for prompt changes
- Cache eviction strategies (current: never, future: time-based)
- Content+window hash computation
- User-edited entry preservation (unimplemented UI)
- Cache management operations (regeneration, purge, selective)
- Performance implications and optimization (viewport pruning)
- Testing strategies and debugging workflows
