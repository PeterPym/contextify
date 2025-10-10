Got it. I’m treating your numbered replies as approvals on the P0/P1 fixes (including the “content-in-DB” correction) and **mandating greenfield**. Below is a clean, consolidated reflow that removes every migration/dual-write vestige, standardizes keys, and folds in the additional feedback (ingestion state, parse errors, PK/FK consistency, progress UI, WAL thresholds). Phase 2 is defined but deferred.

---

# SQLite Backend Architecture (Greenfield, v1)

**Date:** 2025-10-10
**Scope:** macOS app only (single user, offline-first). No server/sync/CloudKit.
**Core model:** **Hoover + Stream**: parse external JSONL transcripts into SQLite; **store parsed message content** + derived data; transcripts remain external sources.

---

## 0) Non-Goals (v1)

* No network sync/CloudKit/server; local-only DB.
* No at-rest DB encryption (revisit in v1.x).
* No FTS (add in Phase 2).
* No job/queue tables (regen stays in-memory).
* No legacy cache reads or dual-write; **all derived data is regenerated**.
* No export features (Phase 2+).
* Rollback = drop/recreate the local DB (derived data is reproducible).

---

## 1) Canonical vocabulary (v1)

* **project** – workspace rooted at a code directory.
* **transcript** – an external provider JSONL file; tracked in DB with ingestion state.
* **entry** – a parsed message line from a transcript; **DB stores the content**.
* **metadata** – LLM-generated title/description/topics per transcript (derived).
* **timeline cache** – rendered entry (disposition + tense forms) keyed by `(content_hash, window_hash)`; device-local and rebuildable.

*Provider truth:* Claude Code & Codex CLI produce JSONL files. We read files, persist messages, **do not** manage file lifecycle.

---

## 2) Key decisions (locked)

* **Greenfield only.** No file-cache migration, no dual-write.
* **IDs:** Use **UUID `TEXT PRIMARY KEY`** for all first-class entities we create (cross-device stable in the future); **no AUTOINCREMENT** elsewhere.
* **FKs:** All cross-table references use the **same key type** (UUID TEXT).
* **Store content in DB.** `entry.content` + `content_sha256` for cache and queryability.
* **Project scoping is via `project_id` FK**, never a raw path string in children.

---

## 3) DDL — single, authoritative (v1 only)

> Booleans = `INTEGER` (0/1). Timestamps = `INTEGER` epoch seconds.
> All tables have `created_at`, `updated_at` set by the app (no DB defaults).

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

/* ---------- project ---------- */
CREATE TABLE project (
  id            TEXT PRIMARY KEY,             -- UUID
  name          TEXT,
  root_path     TEXT NOT NULL,
  root_bookmark BLOB,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE UNIQUE INDEX idx_project_root_path ON project(root_path);

/* ---------- transcripts (external file refs + ingestion state) ---------- */
CREATE TABLE transcripts (
  id                   TEXT PRIMARY KEY,      -- UUID (see §4: id generation)
  project_id           TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  file_path            TEXT NOT NULL,
  provider             TEXT NOT NULL CHECK (provider IN ('claude.code','codex.cli','other')),
  provider_session_id  TEXT,                  -- optional: provider’s logical session id
  last_modified        INTEGER NOT NULL,      -- file mtime
  file_size            INTEGER,
  line_count           INTEGER,
  bookmark             BLOB,                  -- security-scoped
  -- ingestion state
  last_processed_line  INTEGER NOT NULL DEFAULT 0,
  parser_version       INTEGER NOT NULL DEFAULT 1,
  status               TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','unavailable','error')),
  last_error           TEXT,
  -- bookkeeping
  created_at           INTEGER NOT NULL,
  updated_at           INTEGER NOT NULL,
  UNIQUE(project_id, file_path)
);
CREATE INDEX idx_transcripts_project ON transcripts(project_id, updated_at DESC);

/* ---------- transcript_entries (parsed messages; content persisted) ---------- */
CREATE TABLE transcript_entries (
  id            TEXT PRIMARY KEY,             -- UUID per line (provider or deterministic)
  transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
  project_id    TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  session_id    TEXT,                          -- provider’s logical conversation id (optional)
  provider      TEXT NOT NULL CHECK (provider IN ('claude.code','codex.cli','other')),
  kind          TEXT NOT NULL CHECK (kind IN ('user','assistant','system')),
  timestamp     INTEGER NOT NULL,              -- when the message occurred
  content       TEXT NOT NULL,
  content_sha256 TEXT NOT NULL,                -- for cache joins / integrity
  summary       TEXT,                          -- lightweight derived line summary (optional)
  disposition   TEXT,                          -- UI hint (e.g., "success","warning")
  display_in_timeline INTEGER NOT NULL DEFAULT 1,
  is_completion INTEGER NOT NULL DEFAULT 0,
  is_directive  INTEGER NOT NULL DEFAULT 0,
  parent_id     TEXT,                          -- parent entry UUID when threading exists
  git_branch    TEXT,
  git_commit    TEXT,
  cwd           TEXT,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE INDEX idx_entries_transcript_time ON transcript_entries(transcript_id, timestamp);
CREATE INDEX idx_entries_project_time    ON transcript_entries(project_id, timestamp DESC);
CREATE INDEX idx_entries_project_feed    ON transcript_entries(project_id, timestamp DESC)
  WHERE display_in_timeline = 1;
CREATE INDEX idx_entries_content_sha     ON transcript_entries(content_sha256);

/* ---------- timeline_cache (derived; composite PK matches lookup behavior) ---------- */
CREATE TABLE timeline_cache (
  content_hash        TEXT NOT NULL,
  window_hash         TEXT NOT NULL,
  entry_id            TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
  generator_signature TEXT NOT NULL,
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
  PRIMARY KEY (content_hash, window_hash)
);
CREATE UNIQUE INDEX idx_cache_entry_window ON timeline_cache(entry_id, window_hash);

/* ---------- transcript_metadata (derived per transcript; scoped to project) ---------- */
CREATE TABLE transcript_metadata (
  transcript_id        TEXT PRIMARY KEY REFERENCES transcripts(id) ON DELETE CASCADE,
  project_id           TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  title                TEXT NOT NULL,
  description          TEXT NOT NULL,
  topics               TEXT NOT NULL,         -- JSON array in TEXT
  confidence           REAL NOT NULL,
  may_contain_hallucinations INTEGER NOT NULL DEFAULT 0,
  needs_review         INTEGER NOT NULL DEFAULT 0,
  generated_at         INTEGER NOT NULL,
  model                TEXT NOT NULL,
  prompt_version       INTEGER NOT NULL,
  generator_version    INTEGER NOT NULL,
  transcript_sha256    TEXT NOT NULL,
  message_count        INTEGER NOT NULL,
  strategy             TEXT NOT NULL CHECK (strategy IN ('full','bookends','heuristic')),
  llm_calls            INTEGER NOT NULL,
  latency_ms           INTEGER NOT NULL,
  created_at           INTEGER NOT NULL,
  updated_at           INTEGER NOT NULL
);
CREATE INDEX idx_tmeta_needs_review ON transcript_metadata(needs_review);
CREATE INDEX idx_tmeta_stale       ON transcript_metadata(prompt_version, generator_version);

/* ---------- parse_errors (diagnostics; hoover continues on bad lines) ---------- */
CREATE TABLE parse_errors (
  id            TEXT PRIMARY KEY,             -- UUID
  transcript_id TEXT NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
  line_number   INTEGER NOT NULL,
  raw_line      TEXT NOT NULL,
  error_message TEXT NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE INDEX idx_parse_errors_transcript ON parse_errors(transcript_id);
```

**Deferred to Phase 2 (defined, not created now):**

* `entry_fts` / `artifact_fts` (FTS5 + triggers)
* `artifact`, `task`, `ai_job`, `feedback`, `branch`, `sync_state`
* `tool_calls` (only if we actually aggregate/render them)

---

## 4) Identity & generation rules

* **project.id** – `UUID().uuidString` on create.
* **transcripts.id** – **Preferred:** provider’s stable session UUID; **else:** `UUID()`; never derive from `file_path` (path moves would break identity).
* **transcript_entries.id** – **Claude:** use provided line UUID; **Codex:** deterministic UUID from `(timestamp|role|lineNumber|providerSession)` hash to keep re-parses idempotent.
* **content_sha256** – SHA256 of canonicalized `content` (post-parse); stable across re-parses.

All FKs reference these **TEXT UUID** primary keys. No integer surrogates.

---

## 5) Data access & repos (uniform FK strategy)

```swift
protocol ProjectRepo {
  func create(name: String?, rootPath: String, bookmark: Data?) throws -> String
  func list() throws -> [Project]
}

protocol TranscriptRepo {
  func upsert(projectID: String, fileURL: URL, provider: String,
              providerSessionID: String?, lastModified: Int, fileSize: Int?) throws -> String
  func setIngestionState(id: String, lastProcessedLine: Int, parserVersion: Int,
                         status: String, lastError: String?) throws
  func byProject(_ projectID: String) throws -> [Transcript]
}

protocol EntryRepo {
  func insertBatch(_ rows: [EntryNew]) throws                    // rows contain entry.id (UUID)
  func recentByProject(_ projectID: String, limit: Int) throws -> [Entry]
  func byTranscript(_ transcriptID: String, after ts: Int?) throws -> [Entry]
}

protocol MetadataRepo {
  func upsert(_ row: TranscriptMetadataRow) throws
  func get(_ transcriptID: String) throws -> TranscriptMetadataRow?
  func stale(promptVersion: Int, generatorVersion: Int) throws -> [String]
}

protocol CacheRepo {
  func get(contentHash: String, windowHash: String) throws -> CachedTimeline?
  func upsert(_ row: CachedTimeline) throws
}
```

---

## 6) Hoover + Stream (runtime)

**Hoover (first discovery / new project):**

* Scan provider roots per project; create/update `transcripts`.
* For each transcript: read all lines in chunks (e.g., 1k), parse to entries, **`insertBatch` in a single transaction per chunk**, update `last_processed_line` and `updated_at`.
* Save progress every 500 lines or 250 ms (whichever first). On parse error, insert `parse_errors` and continue.

**Stream (file watcher events):**

* Read from `last_processed_line + 1` to EOF.
* Parse and batch insert (small batch, e.g., 50–100).
* Update `last_processed_line`, `last_modified`, `updated_at`.
* UI observes recent feed by `project_id` and updates in ~<500ms p95 path.

---

## 7) Progress UI (explicit contract)

```swift
protocol IngestProgressSink {
  func didStartTranscript(name: String, totalLines: Int?)
  func didAdvance(linesProcessed: Int, totalLines: Int?)
  func didCompleteTranscript(durationMs: Int)
  func didFailTranscript(error: String)
}
```

Sample strings:

* “Importing transcripts… **12/47** complete”
* “Current: `session-abc.jsonl` **7,453 / 12,091** lines”
* “Elapsed: **00:42** • Estimated remaining: **02:15**”

---

## 8) Operational settings & health

* SQLite init:

  ```swift
  config.foreignKeysEnabled = true
  prepareDatabase {
    try db.execute(sql: "PRAGMA journal_mode=WAL;")
    try db.execute(sql: "PRAGMA synchronous=NORMAL;")
    try db.execute(sql: "PRAGMA wal_autocheckpoint=1000;") // ~4–8MB
    try db.execute(sql: "PRAGMA temp_store=MEMORY;")
  }
  ```
* **WAL monitoring:** if WAL > ~50MB, log warning and checkpoint:

  * Log: `db.checkpoint` with wal_bytes_before/after.
  * Action: `PRAGMA wal_checkpoint(TRUNCATE);` on idle.
* **Startup gate:** `PRAGMA quick_check;` and a canary select; on failure block UI, offer drop/recreate.
* **ANALYZE:** weekly; **VACUUM:** monthly or >25% bloat (manual button OK).

---

## 9) Performance targets (v1)

| Action                                  | p95 Target |
| --------------------------------------- | ---------- |
| DB open + quick_check                   | ≤ 150 ms   |
| Recent feed (project, 50k entries)      | ≤ 5 ms     |
| Hoover batch insert (1k rows)           | ≤ 40 ms    |
| Stream insert (≤100 rows)               | ≤ 20 ms    |
| Cache lookup (content_hash+window_hash) | ≤ 5 ms     |
| Metadata upsert                         | ≤ 2 ms     |

**Slow-query logging:** `db.query.slow` ≥ 50ms; include `sql_hash`, `row_count`.

---

## 10) Security & privacy (practical)

* DB under `~/Library/Application Support/Contextify/transcripts.db` (0600).
* External file access via security-scoped bookmarks on `transcripts`.
* Store only messages + derived summaries; no credentials/tokens.

---

## 11) Quality gates (lean)

* **Integrity:** FK cascade delete (transcript → entries/cache/metadata/parse_errors).
* **Idempotence:** deterministic `entry.id` for Codex; `ON CONFLICT(id) DO NOTHING` semantics in repo.
* **Scale:** fixture with ≥50k entries; assert p95s.
* **Edge cases:** truncated file (status=`unavailable` + re-hoover), parser version bump (reset `last_processed_line=0`, `parser_version++`), duplicated lines (UUID conflict ignored).

---

## 12) Phasing

* **Phase 1 (this release):** project/transcripts/entries/metadata/timeline_cache/parse_errors; hoover + stream; no FTS; no mobile tables.
* **Phase 2 (deferred, defined):**

  * **FTS:** `entry_fts` with triggers; optional `artifact_fts`.
  * **Mobile entities:** `artifact`, `task`, `ai_job`, `feedback`, `branch`.
  * **Sync scaffolding:** `sync_state(entity, entity_id, remote_id, is_dirty, last_pushed_at, last_pulled_at)`.
  * (Optional) `tool_calls` if/when we render/aggregate.

---

## 13) Open/closed items (post-reflow)

**Closed (implemented in this reflow):**

* Greenfield mandate (no migration/dual-write mentions).
* `project_id` scoping; no `project_path` in children.
* `transcript_id` FK in entries; standardized UUID TEXT PKs.
* `timeline_cache` composite PK; `(entry_id, window_hash)` unique.
* Ingestion state columns + `parse_errors`.
* `content_sha256` plus index.
* Single canonical DDL.

**Assumptions (acceptable risk):**

* Providers keep stable per-message UUIDs (Claude) or enough fields for deterministic hash (Codex).
* Single-writer process; no concurrent writers to DB.

---

## 14) Pre-implementation checklist

* [ ] Wire GRDB with PRAGMAs above; create schema exactly as §3.
* [ ] Implement deterministic `entry.id` generator for Codex.
* [ ] Implement hoover with chunked transactions + progress sink.
* [ ] Implement watcher stream path and resume logic.
* [ ] Implement cache repo keyed by `(content_hash, window_hash)`.
* [ ] Surface slow-query logs with `sql_hash` and `row_count`.
* [ ] Ship fixture/perf tests hitting p95 targets.

---

**Bottom line:** This version is internally consistent, greenfield-clean, and minimal. It stores message content (so your analytics actually work), scopes everything by `project_id`, pins cache identity to `(content_hash, window_hash)`, and leaves FTS/mobile/sync to a crisp Phase 2.
