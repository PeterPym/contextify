# v4 Final Delta Pack - Apply to sql-implementation-plan-04.md

**Date:** 2025-10-10
**Purpose:** Final production refinements for v4 spec
**Status:** Ready to integrate

---

## 1. Schema & Index Touch-Ups

### Replace §4.2 Completion Index

**OLD:**
```sql
CREATE INDEX idx_entries_completion      ON transcript_entries(project_id, is_completion)
  WHERE is_completion = 1;
```

**NEW (order-friendly):**
```sql
CREATE INDEX idx_entries_completion
  ON transcript_entries(project_id, is_completion, timestamp DESC)
  WHERE is_completion = 1;
```

---

### Add to §4.2 After `idx_transcripts_status`

**NEW (fast provider session lookup):**
```sql
CREATE INDEX idx_transcripts_provider_session
  ON transcripts(provider_session_id)
  WHERE provider_session_id IS NOT NULL;
```

**Optional uniqueness constraint (if providers are stable per project):**
```sql
-- Uncomment if provider_session_id is proven stable:
-- CREATE UNIQUE INDEX uq_transcripts_provider_session_scoped
--   ON transcripts(project_id, provider, provider_session_id)
--   WHERE provider_session_id IS NOT NULL;
```

---

### Replace §4.2 Timeline Cache Table

**OLD:**
```sql
CREATE TABLE timeline_cache (
  content_sha256      TEXT NOT NULL,
  window_sha256       TEXT NOT NULL,
  ...
  PRIMARY KEY (content_sha256, window_sha256)
);
```

**NEW (add `WITHOUT ROWID` for composite PK optimization):**
```sql
CREATE TABLE timeline_cache (
  content_sha256      TEXT NOT NULL,          -- SHA256(entry.content)
  window_sha256       TEXT NOT NULL,          -- SHA256 of context window UUIDs
  entry_id            TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
  generator_signature TEXT NOT NULL,          -- "{model}@{ver}:{prompt}@{ver}"
  disposition         TEXT NOT NULL,
  present_form        TEXT NOT NULL,
  past_form           TEXT NOT NULL,
  selected_form       TEXT NOT NULL CHECK (selected_form IN ('present','past')),
  verb_lemma          TEXT,
  generated_at        INTEGER NOT NULL,
  user_edited         INTEGER NOT NULL DEFAULT 0,
  user_text           TEXT,
  edited_at           INTEGER,
  request_id          TEXT,
  duration            REAL,
  PRIMARY KEY (content_sha256, window_sha256)
) WITHOUT ROWID;
CREATE UNIQUE INDEX idx_cache_entry_window ON timeline_cache(entry_id, window_sha256);
```

---

### Update §4.2 Parse Errors Comment

**OLD:**
```sql
/* ========== PARSE ERRORS (Diagnostics; Hoover Continues on Bad Lines) ========== */
-- raw_line truncated to ≤4096 bytes; keep last 500 per transcript
```

**NEW (relaxed, diagnostics-focused):**
```sql
/* ========== PARSE ERRORS (Diagnostics; Hoover Continues on Bad Lines) ========== */
-- raw_line is diagnostics-only; truncate to ~1K chars (~1-4KB UTF-8)
-- Keep last 500 per transcript
```

---

## 2. Algorithm Clarifications

### Add to §5.3 After `window_sha256` Algorithm

**NEW (empty context behavior):**
```
**Empty context:**
If both `prev2` and `prev1` are `nil`, the window string is `"|"` (two empty slots joined by pipe), and we hash that string.

Example: `SHA256("|")` → `4bf5...`
```

---

### Add to §5.3 After `generator_signature` Format

**NEW (helper struct):**
```swift
/// Helper for constructing/parsing generator signatures
struct GeneratorSignature {
    let model: String          // e.g., "gpt-4o"
    let modelVersion: String   // e.g., "2025-09"
    let prompt: String         // e.g., "timeline"
    let promptVersion: String  // e.g., "3"

    var string: String {
        "\(model)@\(modelVersion):\(prompt)@\(promptVersion)"
    }

    static func parse(_ sig: String) -> GeneratorSignature? {
        let parts = sig.split(separator: ":")
        guard parts.count == 2 else { return nil }
        let m = parts[0].split(separator: "@")
        let p = parts[1].split(separator: "@")
        guard m.count == 2, p.count == 2 else { return nil }
        return .init(
            model: String(m[0]),
            modelVersion: String(m[1]),
            prompt: String(p[0]),
            promptVersion: String(p[1])
        )
    }
}
```

---

### Add New §5.4: transcript_sha256 Definition

**NEW:**
```markdown
## 5.4 Transcript SHA256 (Logical Stream Hash)

**Definition:**

`transcript_sha256` = SHA256 over the **logical transcript stream**: the exact UTF-8 bytes of each JSONL line as read during hoover, joined with `\n` in the same order.

**Computation:**

Compute **incrementally** while streaming:

```swift
var hasher = SHA256()

// During hoover loop (per line)
hasher.update(data: lineData)  // Raw line bytes
hasher.update(data: Data([0x0A]))  // Newline

// After hoover completes
let finalHash = hasher.finalize()
let transcriptSHA256 = finalHash.compactMap { String(format: "%02x", $0) }.joined()

// Store in transcript_metadata.transcript_sha256
```

**Purpose:** Detects transcript file changes (provider edits, re-writes) without re-reading entire file.
```

---

## 3. Streaming Parser Fixes

### Replace §7.1 Config Constants

**OLD:**
```swift
enum MonitorConfig {
    static let fileWatcherDebounce: TimeInterval = 0.150
    static let batchLines: Int = 1000
    static let checkpointEveryLines: Int = 1000
    static let parseErrorMaxLineLength: Int = 4096        // bytes
    static let parseErrorRetentionPerTranscript: Int = 500
}
```

**NEW (relaxed char limit, explicit):**
```swift
enum MonitorConfig {
    static let fileWatcherDebounce: TimeInterval = 0.150  // seconds
    static let batchLines: Int = 1000
    static let checkpointEveryLines: Int = 1000
    static let parseErrorMaxChars: Int = 1024             // chars (~1-4KB UTF-8)
    static let parseErrorRetentionPerTranscript: Int = 500
}
```

---

### Update §7.2 Hoover Parser - Add EOF Handling

**After the main `while` loop (line ~547), BEFORE "// Final batch":**

**ADD (handle partial line at EOF):**
```swift
    // Handle final partial line (no trailing newline)
    if !buffer.isEmpty, let lineString = String(data: buffer, encoding: .utf8) {
        lineNo += 1
        do {
            let entry = try parseTranscriptLine(
                lineString,
                provider: transcript.provider,
                lineNumber: lineNo,
                sessionID: transcript.provider_session_id
            )
            batch.append(entry)
        } catch {
            let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
            errors.append(ParseError(
                transcriptID: transcript.id,
                lineNumber: lineNo,
                rawLine: truncated,
                errorMessage: error.localizedDescription
            ))
        }
        buffer.removeAll()
    }
```

---

### Update §7.2 Parse Error Truncation (2 places)

**FIND (lines ~524 and new EOF handler):**
```swift
let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxLineLength))
```

**REPLACE WITH:**
```swift
let truncated = String(lineString.prefix(MonitorConfig.parseErrorMaxChars))
```

---

### Update §9.1 Progress Protocol (add doc comments)

**OLD:**
```swift
protocol IngestProgressSink {
    func didStartTranscript(name: String, totalLines: Int?)
    func didAdvance(linesProcessed: Int, totalLines: Int?)
    func didCompleteTranscript(durationMs: Int)
    func didFailTranscript(error: String)
    func didStartProject(name: String, transcriptCount: Int)
    func didCompleteProject(name: String)
}
```

**NEW (with doc comments):**
```swift
protocol IngestProgressSink {
    /// Called once at start. totalLines may be nil if unknown.
    func didStartTranscript(name: String, totalLines: Int?)

    /// Called repeatedly during processing. totalLines can be nil if already provided.
    func didAdvance(linesProcessed: Int, totalLines: Int?)

    func didCompleteTranscript(durationMs: Int)
    func didFailTranscript(error: String)
    func didStartProject(name: String, transcriptCount: Int)
    func didCompleteProject(name: String)
}
```

---

### Update §12.2 Path Canonicalization

**OLD:**
```swift
func canonicalizePath(_ path: String) -> String {
    let url = URL(fileURLWithPath: path)
    return url.standardizedFileURL.path  // Resolves symlinks, normalizes
}
```

**NEW (explicit symlink resolution):**
```swift
func canonicalizePath(_ path: String) -> String {
    URL(fileURLWithPath: path)
        .resolvingSymlinksInPath()
        .standardizedFileURL
        .path
}
```

---

## 4. ON CONFLICT Simplification

### Replace §7.4 Entirely

**OLD (two variants):**
```
## 7.4 ON CONFLICT Policies (Explicit)

**Initial hoover / normal stream:** Deduplicate silently
[...]
**Re-parse after provider format change (rare):** Update only if content changed
[...]
```

**NEW (single policy, cleaner):**
```markdown
## 7.4 ON CONFLICT Policy

**All ingestion paths use silent deduplication:**

```sql
INSERT INTO transcript_entries (id, content, content_sha256, ...)
VALUES (?, ?, ?, ...)
ON CONFLICT(id) DO NOTHING;
```

**Rationale:**
- Parser upgrades use DELETE + re-hoover (§7.6), not UPDATE
- Idempotent re-parsing: same line → same entry.id → skipped via conflict
- No UPDATE variant needed in production
```

---

## 5. Diagnostics & Invariants

### Add New §13.4: Denormalization Spot Check

**NEW (after §13.3):**
```markdown
## 13.4 Denormalization Invariant Check

**Diagnostic query (should return no rows):**

```sql
-- Any entry whose project_id disagrees with its transcript's project?
SELECT e.id, e.project_id AS entry_project, t.project_id AS transcript_project
FROM transcript_entries e
LEFT JOIN transcripts t ON t.id = e.transcript_id
WHERE t.project_id IS NULL
   OR e.project_id <> t.project_id
LIMIT 1;
```

**When to run:**
- During development (unit tests)
- After major refactoring
- In diagnostics panel (debug builds)

**Expected result:** Empty (no rows = all denorms consistent)
```

---

## 6. Final Acceptance Checks

### Replace §16 "Before shipping" Checklist

**OLD:**
```
**Before shipping:**

- [ ] Run performance tests (hit p95 targets)
- [ ] Test with 50k line transcript
- [ ] Verify FK cascade deletes
- [ ] Check WAL checkpointing
- [ ] Test parser error handling
- [ ] Verify parse error retention (only last 500)
- [ ] Test concurrent reads (DatabasePool)
```

**NEW (add final checks):**
```markdown
**Before shipping:**

- [ ] Run performance tests (hit p95 targets)
- [ ] Test with 50k line transcript
- [ ] Verify FK cascade deletes
- [ ] Check WAL checkpointing
- [ ] Test parser error handling
- [ ] Verify parse error retention (only last 500)
- [ ] Test concurrent reads (DatabasePool)
- [ ] Symlink-resolving path canonicalization verified
- [ ] Partial-line EOF path covered (unit test)
- [ ] Relaxed parse-error truncation (~1K chars) in place
- [ ] Single ON CONFLICT policy (DO NOTHING) reflected in §7.4
- [ ] `timeline_cache` created `WITHOUT ROWID`
- [ ] Provider session index present; lookup tested
- [ ] Completion partial index includes `timestamp DESC`
- [ ] `transcript_sha256` computed incrementally during hoover
- [ ] Denorm spot-check returns no rows on fixtures (§13.4)
```

---

## Summary of Changes

| Category | Change | Impact |
|----------|--------|--------|
| **Schema** | Completion index includes `timestamp DESC` | Better ORDER BY perf |
| **Schema** | Provider session index added | Fast session lookups |
| **Schema** | `timeline_cache WITHOUT ROWID` | Smaller, faster composite PK |
| **Schema** | Parse error comment relaxed (~1K chars) | Clearer intent |
| **Algorithms** | Empty `window_sha256` behavior defined | No ambiguity |
| **Algorithms** | `GeneratorSignature` helper struct | Easier to parse/construct |
| **Algorithms** | `transcript_sha256` defined (§5.4) | Incremental hash spec |
| **Streaming** | EOF partial line handler added | Correctness (no trailing \n) |
| **Streaming** | Truncation uses `parseErrorMaxChars` | Consistent config |
| **Streaming** | Path canonicalize uses `resolvingSymlinksInPath()` | Explicit symlink resolution |
| **Protocol** | Progress sink doc comments added | Clearer contract |
| **Conflict** | Simplified to single `DO NOTHING` policy | Less confusion |
| **Diagnostics** | Denorm spot-check query (§13.4) | Catch invariant violations |
| **Checklist** | 9 additional pre-ship checks | Comprehensive validation |

---

**Total Additions:** ~150 lines
**Total Modifications:** ~20 lines
**Total Effort:** +2 units (~20 minutes)

**Final Estimated Effort:** ~28 units (~280 minutes = ~4.7 hours of core changes)

---

**Document Status:** Ready to Integrate
**Version:** 4.0.1 (final delta)
**Next:** Apply this delta → v4 becomes final production spec
