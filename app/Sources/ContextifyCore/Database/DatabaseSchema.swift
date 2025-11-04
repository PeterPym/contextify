import Foundation
import GRDB

/// SQLite schema for Contextify transcript storage
/// Current version: v22 (fixed strategy CHECK constraint to include adaptive/signalFirst)
///
/// Time Unit Convention:
/// - Standard timestamps (created_at, updated_at, generated_at, timestamp, last_modified): Unix seconds (Int)
/// - High-precision timestamps (mtime_ms, latency_ms, created_ts, last_viewed_ts): Epoch seconds (Double) for unread tracking
/// - Rationale: Double epoch seconds preserve millisecond precision for unread queries while avoiding float rounding
enum DatabaseSchema {
  static let version = 23

  /// Create migrator for schema evolution
  static func createMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    // v16: Collapsed schema (all previous migrations merged)
    // Existing v16 databases will skip this (migration already applied)
    // Fresh databases get full v16 schema immediately
    migrator.registerMigration("v16_collapsed_schema") { db in
      try createV16Schema(db)
    }

    // v17: Comprehensive fixes for v16 collapse issues
    // - Backfills for created_ts and last_viewed_ts (fixes unread tracking)
    // - Restore missing indexes from pre-collapse
    // - Rebuild assistant_usage_pending with composite PK
    // - Fix trigger with explicit DROP + CREATE
    // - Add missing transcript_metadata table
    migrator.registerMigration("v17_schema_fixes") { db in
      // ========================================================================
      // BACKFILLS (CRITICAL - fixes unread tracking)
      // ========================================================================

      // Backfill created_ts from timestamp for entries that lack it
      try db.execute(sql: """
        UPDATE transcript_entries
        SET created_ts = CAST(timestamp AS REAL)
        WHERE created_ts IS NULL
      """)

      // Backfill last_viewed_ts from project_visits legacy data
      try db.execute(sql: """
        UPDATE projects
        SET last_viewed_ts = MAX(
          COALESCE(last_viewed_ts, 0),
          COALESCE((
            SELECT MAX(strftime('%s', pv.last_viewed_at))
            FROM project_visits pv
            WHERE pv.project_id = projects.id
              AND pv.last_viewed_at IS NOT NULL
              AND pv.last_viewed_at <> ''
          ), 0)
        )
        WHERE last_viewed_ts = 0
      """)

      // Fix 1: Add missing columns to system_events
      let systemEventsInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(system_events)")
      let existingColumns = Set(systemEventsInfo.map { $0["name"] as! String })

      if !existingColumns.contains("retry_in_ms") {
        try db.execute(sql: "ALTER TABLE system_events ADD COLUMN retry_in_ms INTEGER")
      }
      if !existingColumns.contains("parent_uuid") {
        try db.execute(sql: "ALTER TABLE system_events ADD COLUMN parent_uuid TEXT")
      }
      if !existingColumns.contains("logical_parent_uuid") {
        try db.execute(sql: "ALTER TABLE system_events ADD COLUMN logical_parent_uuid TEXT")
      }
      if !existingColumns.contains("compact_metadata") {
        try db.execute(sql: "ALTER TABLE system_events ADD COLUMN compact_metadata TEXT")
      }

      // ========================================================================
      // MISSING INDEXES (PERFORMANCE REGRESSION)
      // ========================================================================

      // Index for entries→transcripts JOINs
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_transcripts_project_id
        ON transcripts(project_id)
      """)

      // Index for transcript-scoped timeline queries
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_transcript_created_ts_timeline
        ON transcript_entries(transcript_id, created_ts)
        WHERE display_in_timeline = 1
      """)

      // Index for cursor-based pagination (if still used)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_cursor
        ON transcript_entries(project_id, timestamp, created_at, id)
        WHERE display_in_timeline = 1
      """)

      // ========================================================================
      // ASSISTANT_USAGE_PENDING REBUILD WITH COMPOSITE PK
      // ========================================================================

      // Create new table with composite PK and DEFAULT created_at
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS assistant_usage_pending_new (
          entry_id TEXT NOT NULL,
          request_id TEXT NOT NULL,
          model TEXT NOT NULL,
          input_tokens INTEGER NOT NULL,
          output_tokens INTEGER NOT NULL,
          cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
          cache_read_tokens INTEGER NOT NULL DEFAULT 0,
          service_tier TEXT,
          ephemeral_5m_tokens INTEGER NOT NULL DEFAULT 0,
          ephemeral_1h_tokens INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
          PRIMARY KEY(entry_id, request_id)
        )
      """)

      // Copy data with deduplication (take earliest created_at per key)
      let hasOldTable = try db.tableExists("assistant_usage_pending")
      if hasOldTable {
        try db.execute(sql: """
          INSERT OR REPLACE INTO assistant_usage_pending_new
          SELECT
            entry_id,
            COALESCE(NULLIF(request_id,''), entry_id) as request_id,
            model,
            input_tokens,
            output_tokens,
            COALESCE(cache_creation_tokens, 0),
            COALESCE(cache_read_tokens, 0),
            service_tier,
            COALESCE(ephemeral_5m_tokens, 0),
            COALESCE(ephemeral_1h_tokens, 0),
            MIN(COALESCE(created_at, CAST(strftime('%s','now') AS INTEGER)))
          FROM assistant_usage_pending
          GROUP BY entry_id, COALESCE(NULLIF(request_id,''), entry_id)
        """)
        try db.drop(table: "assistant_usage_pending")
      }
      try db.rename(table: "assistant_usage_pending_new", to: "assistant_usage_pending")

      // Recreate indexes on pending table
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_pending_entry_request
        ON assistant_usage_pending(entry_id, request_id)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_pending_created
        ON assistant_usage_pending(created_at)
      """)

      // ========================================================================
      // FIX TRIGGER (EXPLICIT DROP + CREATE)
      // ========================================================================

      // Drop any existing triggers to ensure clean slate
      try db.execute(sql: "DROP TRIGGER IF EXISTS assistant_usage_before_insert")
      try db.execute(sql: "DROP TRIGGER IF EXISTS trg_assistant_usage_stage")

      // Recreate with staging semantics (RAISE(IGNORE))
      try db.execute(sql: """
        CREATE TRIGGER trg_assistant_usage_stage
        BEFORE INSERT ON assistant_usage
        FOR EACH ROW
        WHEN NOT EXISTS (SELECT 1 FROM transcript_entries WHERE id = NEW.entry_id)
        BEGIN
          INSERT OR REPLACE INTO assistant_usage_pending (
            entry_id, request_id, model, input_tokens, output_tokens,
            cache_creation_tokens, cache_read_tokens, service_tier,
            ephemeral_5m_tokens, ephemeral_1h_tokens
          ) VALUES (
            NEW.entry_id,
            COALESCE(NULLIF(NEW.request_id,''), NEW.entry_id),
            NEW.model, NEW.input_tokens, NEW.output_tokens,
            COALESCE(NEW.cache_creation_tokens,0), COALESCE(NEW.cache_read_tokens,0),
            NEW.service_tier,
            COALESCE(NEW.ephemeral_5m_tokens,0), COALESCE(NEW.ephemeral_1h_tokens,0)
          );
          SELECT RAISE(IGNORE);
        END
      """)

      // Fix 4: Add transcript_metadata table if missing
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS transcript_metadata (
          transcript_id TEXT PRIMARY KEY NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          description TEXT NOT NULL,
          topics TEXT NOT NULL CHECK(json_valid(topics)),
          confidence REAL NOT NULL,
          may_contain_hallucinations INTEGER NOT NULL DEFAULT 0,
          needs_review INTEGER NOT NULL DEFAULT 0,
          generated_at INTEGER NOT NULL,
          model TEXT NOT NULL,
          prompt_version INTEGER NOT NULL,
          generator_version INTEGER NOT NULL,
          transcript_sha256 TEXT NOT NULL,
          message_count INTEGER NOT NULL,
          strategy TEXT NOT NULL CHECK(strategy IN ('full','adaptive','bookends','signalFirst','heuristic')),
          llm_calls INTEGER NOT NULL,
          latency_ms INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      """)

      // Add missing indexes
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_project ON transcript_metadata(project_id)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_generated_at ON transcript_metadata(generated_at DESC)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_needs_review ON transcript_metadata(needs_review, generated_at DESC)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_sha ON transcript_metadata(transcript_sha256)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_events_timestamp ON system_events(timestamp)")

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // v18: Add hidden column for project visibility management
    migrator.registerMigration("v18_project_hidden_column") { db in
      // Guard against clean installs where column already exists
      if try !db.columnExists("hidden", in: "projects") {
        try db.execute(sql: "ALTER TABLE projects ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0")

        // Add index for filtering hidden projects
        try db.execute(sql: """
          CREATE INDEX IF NOT EXISTS idx_projects_hidden
          ON projects(hidden)
          WHERE hidden = 1
        """)
      }
    }

    // v19: Add display_order column for custom project ordering
    migrator.registerMigration("v19_project_display_order") { db in
      // Guard against clean installs where column already exists
      if try !db.columnExists("display_order", in: "projects") {
        try db.execute(sql: "ALTER TABLE projects ADD COLUMN display_order INTEGER")

        // Backfill existing projects with ascending order based on (created_at, id) for determinism
        try db.execute(sql: """
          UPDATE projects
          SET display_order = (
            SELECT COUNT(*) FROM projects p2
            WHERE p2.created_at < projects.created_at
               OR (p2.created_at = projects.created_at AND p2.id < projects.id)
          )
        """)

        // Add index for ordered queries
        try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_projects_display_order ON projects(display_order)")
      }
    }

    // v20: Add orphaned project tracking columns
    migrator.registerMigration("v20_orphaned_projects") { db in
      // Guard against clean installs where columns already exist
      var didAlter = false
      if try !db.columnExists("is_orphaned", in: "projects") {
        try db.execute(sql: "ALTER TABLE projects ADD COLUMN is_orphaned INTEGER NOT NULL DEFAULT 0")
        didAlter = true
      }
      if try !db.columnExists("orphaned_since", in: "projects") {
        try db.execute(sql: "ALTER TABLE projects ADD COLUMN orphaned_since INTEGER")
        didAlter = true
      }

      // Add partial index for orphaned projects (only if we altered the schema)
      if didAlter {
        try db.execute(sql: """
          CREATE INDEX IF NOT EXISTS idx_projects_orphaned
          ON projects(is_orphaned, orphaned_since)
          WHERE is_orphaned = 1
        """)
      }
    }

    // v21: Add database access metadata for multi-machine conflict detection
    migrator.registerMigration("v21_access_metadata") { db in
      try db.create(table: "database_access_metadata", ifNotExists: true) { t in
        t.column("machine_id", .text).primaryKey()
        t.column("machine_name", .text).notNull()
        t.column("last_access", .datetime).notNull()
        t.column("app_version", .text).notNull()
      }
    }

    // v22: Fix strategy CHECK constraint to include all GenerationStrategy enum values
    // SQLite doesn't support ALTER TABLE to modify CHECK constraints, so we recreate the table
    migrator.registerMigration("v22_strategy_constraint_fix") { db in
      // Check if transcript_metadata table exists
      let tableExists = try db.tableExists("transcript_metadata")
      guard tableExists else { return }

      // Create temp table with corrected CHECK constraint
      try db.execute(sql: """
        CREATE TABLE transcript_metadata_new (
          transcript_id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          topics TEXT NOT NULL,
          confidence REAL NOT NULL,
          may_contain_hallucinations INTEGER NOT NULL,
          needs_review INTEGER NOT NULL,
          generated_at INTEGER NOT NULL,
          model TEXT NOT NULL,
          prompt_version INTEGER NOT NULL,
          generator_version INTEGER NOT NULL,
          transcript_sha256 TEXT NOT NULL,
          message_count INTEGER NOT NULL,
          strategy TEXT NOT NULL CHECK(strategy IN ('full','adaptive','bookends','signalFirst','heuristic')),
          llm_calls INTEGER NOT NULL,
          latency_ms INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (transcript_id) REFERENCES transcripts(id) ON DELETE CASCADE
        )
      """)

      // Copy data
      try db.execute(sql: """
        INSERT INTO transcript_metadata_new
        SELECT * FROM transcript_metadata
      """)

      // Drop old table
      try db.execute(sql: "DROP TABLE transcript_metadata")

      // Rename new table
      try db.execute(sql: "ALTER TABLE transcript_metadata_new RENAME TO transcript_metadata")

      // Recreate indexes
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_project ON transcript_metadata(project_id)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_generated_at ON transcript_metadata(generated_at DESC)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_needs_review ON transcript_metadata(needs_review, generated_at DESC)")
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tm_sha ON transcript_metadata(transcript_sha256)")
    }

    // v23: Active transcript follow - surgical fix for session switching
    migrator.registerMigration("v23_active_transcript_follow") { db in
      // A) Follow policy table
      // F: project_id is TEXT to match projects(id) which is TEXT (path-based primary key)
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS project_follow_policy (
          project_id        TEXT NOT NULL UNIQUE REFERENCES projects(id) ON DELETE CASCADE,
          mode              INTEGER NOT NULL,             -- 0=auto, 1=manual
          pinned_session_id TEXT,
          pinned_provider   TEXT,
          updated_at        TEXT NOT NULL
        )
      """)

      // Initialize policy for existing projects (all start in auto mode)
      try db.execute(sql: """
        INSERT OR IGNORE INTO project_follow_policy(project_id, mode, updated_at)
        SELECT id, 0, strftime('%Y-%m-%dT%H:%M:%SZ','now') FROM projects
      """)

      // B) Provider normalization (codex -> codex.cli)
      try db.execute(sql: """
        UPDATE transcripts SET provider = 'codex.cli' WHERE provider = 'codex'
      """)
      try db.execute(sql: """
        UPDATE transcript_entries SET provider = 'codex.cli' WHERE provider = 'codex'
      """)

      // C) Cursor performance index for deterministic scans
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_cursor
        ON transcript_entries(project_id, timestamp, created_at, id)
      """)

      // D) Add project_id to system_events for project-scoped events
      // P0-1: project_id is TEXT to match projects(id) which is TEXT (path-based primary key)
      // Check if column already exists to avoid errors on re-run
      if try !db.columnExists("project_id", in: "system_events") {
        try db.execute(sql: """
          ALTER TABLE system_events ADD COLUMN project_id TEXT REFERENCES projects(id)
        """)
      }

      // Backfill project_id for existing events (handle both real and synthetic project:<id> IDs)
      try db.execute(sql: """
        UPDATE system_events AS se
           SET project_id = COALESCE(
              (SELECT t.project_id FROM transcripts t WHERE t.id = se.transcript_id),
              CASE WHEN se.transcript_id LIKE 'project:%'
                   THEN substr(se.transcript_id, 9)
                   ELSE NULL END
           )
         WHERE project_id IS NULL
           AND (se.transcript_id IN (SELECT id FROM transcripts)
                OR se.transcript_id LIKE 'project:%')
      """)

      // Create index for project-scoped queries
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_system_events_project
        ON system_events(project_id, timestamp)
      """)

      // E) Add metadata_json column to system_events if missing
      if try !db.columnExists("metadata_json", in: "system_events") {
        try db.execute(sql: """
          ALTER TABLE system_events ADD COLUMN metadata_json TEXT
        """)
      }

      // Update ANALYZE statistics
      try db.execute(sql: "ANALYZE")
    }

    return migrator
  }

  /// Create complete v16 schema for fresh databases
  private static func createV16Schema(_ db: Database) throws {
    try db.execute(sql: "PRAGMA foreign_keys = ON")
    try db.execute(sql: "PRAGMA journal_mode = WAL")

    // Projects table (v12: added last_viewed_ts for unread tracking, v18: added hidden for visibility management, v19: added display_order for custom ordering, v20: added orphaned tracking)
    try db.create(table: "projects", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("name", .text)
      t.column("root_path", .text).notNull()
      t.column("root_bookmark", .blob)
      t.column("last_viewed_ts", .double).notNull().defaults(to: 0.0)  // v12: epoch timestamp
      t.column("hidden", .integer).notNull().defaults(to: 0)  // v18: project visibility
      t.column("display_order", .integer)  // v19: custom project ordering
      t.column("is_orphaned", .integer).notNull().defaults(to: 0)  // v20: orphaned tracking
      t.column("orphaned_since", .integer)  // v20: when directory went missing
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_projects_root_path", on: "projects", columns: ["root_path"], unique: true, ifNotExists: true)
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_projects_hidden
      ON projects(hidden)
      WHERE hidden = 1
    """)
    try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_projects_display_order ON projects(display_order)")
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_projects_orphaned
      ON projects(is_orphaned, orphaned_since)
      WHERE is_orphaned = 1
    """)

    // Transcripts table (v2: last_processed_entry_id, v3: identity fields, v3: unique indexes)
    try db.create(table: "transcripts", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
      t.column("file_path", .text).notNull()
      t.column("provider", .text).notNull().check(sql: "provider IN ('claude.code','codex.cli','other')")
      t.column("provider_session_id", .text)
      t.column("last_modified", .integer).notNull()
      t.column("file_size", .integer)
      t.column("line_count", .integer).notNull().defaults(to: 0)
      t.column("bookmark", .blob)
      // Ingestion state (v2: added last_processed_entry_id)
      t.column("last_processed_line", .integer).notNull().defaults(to: 0)
      t.column("last_processed_entry_id", .text)  // v2: resume checkpoint
      t.column("parser_version", .integer).notNull().defaults(to: 1)
      t.column("status", .text).notNull().defaults(to: "active").check(sql: "status IN ('active','unavailable','error')")
      t.column("last_error", .text)
      // Identity fields (v3: for path-based deduplication)
      t.column("normalized_path", .text)
      t.column("path_hash", .text)
      t.column("content_length", .integer)
      t.column("mtime_ms", .integer)
      t.column("content_sha256", .text)
      // Bookkeeping
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()

      t.uniqueKey(["project_id", "file_path"])
    }
    try db.create(index: "idx_transcripts_project", on: "transcripts", columns: ["project_id", "updated_at"], ifNotExists: true)
    try db.create(index: "idx_transcripts_status", on: "transcripts", columns: ["status"], ifNotExists: true, condition: "status != 'active'")
    try db.create(index: "idx_transcripts_provider_session", on: "transcripts", columns: ["provider_session_id"], ifNotExists: true, condition: "provider_session_id IS NOT NULL")

    // v3: Identity indexes (partial unique constraints)
    try db.execute(sql: """
      CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_session
      ON transcripts(provider, provider_session_id)
      WHERE provider_session_id IS NOT NULL AND provider_session_id <> ''
    """)
    try db.execute(sql: """
      CREATE UNIQUE INDEX IF NOT EXISTS uq_tr_provider_path_hash
      ON transcripts(provider, path_hash)
      WHERE (provider_session_id IS NULL OR provider_session_id = '')
        AND path_hash IS NOT NULL
    """)
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_tr_mtime_ms ON transcripts(mtime_ms)
    """)

    // Transcript entries table (v2: window fields, v4: embeddings, v12: created_ts for unread)
    try db.create(table: "transcript_entries", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
      t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
      t.column("session_id", .text)
      t.column("provider", .text).notNull().check(sql: "provider IN ('claude.code','codex.cli','other')")
      t.column("kind", .text).notNull().check(sql: "kind IN ('user','assistant','system')")
      t.column("timestamp", .integer).notNull()
      t.column("content", .text).notNull()
      t.column("content_sha256", .text).notNull()
      t.column("display_in_timeline", .integer).notNull().defaults(to: 1)
      t.column("parent_id", .text).references("transcript_entries", onDelete: .setNull)
      t.column("git_branch", .text)
      t.column("git_commit", .text)
      t.column("cwd", .text)
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
      // v2: Window tracking for LLM cache keys
      t.column("prev1_id", .text)
      t.column("prev2_id", .text)
      t.column("window_sha256", .text)
      // v4: RAG embeddings
      t.column("embedding", .blob)
      t.column("embedding_version", .integer).defaults(to: 1)
      t.column("embedding_generated_at", .integer)
      // v12: Unread tracking (millisecond-precision epoch timestamp)
      t.column("created_ts", .double)  // Populated from timestamp during ingestion
    }
    try db.create(index: "idx_entries_transcript_time", on: "transcript_entries", columns: ["transcript_id", "timestamp"], ifNotExists: true)
    try db.create(index: "idx_entries_content_sha", on: "transcript_entries", columns: ["content_sha256"], ifNotExists: true)

    // Project time indexes with DESC for ORDER BY performance
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_entries_project_time
      ON transcript_entries(project_id, timestamp DESC)
    """)
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_entries_project_feed
      ON transcript_entries(project_id, timestamp DESC)
      WHERE display_in_timeline = 1
    """)

    // v2: Feed covering index (v6: removed is_completion from column list)
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_entries_feed_cover ON transcript_entries(
        project_id,
        timestamp,
        created_at,
        id,
        content_sha256,
        window_sha256,
        kind,
        session_id
      ) WHERE display_in_timeline = 1
    """)

    // v16: Unread query GROUP BY index
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_entries_unread_join
      ON transcript_entries(project_id, created_ts)
      WHERE display_in_timeline = 1
    """)

    // Timeline cache table (WITHOUT ROWID for composite PK optimization)
    try db.execute(sql: """
      CREATE TABLE IF NOT EXISTS timeline_cache (
        content_sha256 TEXT NOT NULL,
        window_sha256 TEXT NOT NULL,
        entry_id TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
        generator_signature TEXT NOT NULL,
        disposition TEXT NOT NULL,
        present_form TEXT NOT NULL,
        past_form TEXT NOT NULL,
        selected_form TEXT NOT NULL CHECK (selected_form IN ('present','past')),
        verb_lemma TEXT,
        generated_at INTEGER NOT NULL,
        user_edited INTEGER NOT NULL DEFAULT 0,
        user_text TEXT,
        edited_at INTEGER,
        request_id TEXT,
        duration REAL,
        PRIMARY KEY (content_sha256, window_sha256)
      ) WITHOUT ROWID
    """)
    try db.create(index: "idx_cache_entry_window", on: "timeline_cache", columns: ["entry_id", "window_sha256"], unique: true, ifNotExists: true)

    // Transcript metadata table (LLM-generated summaries, titles, topics)
    try db.execute(sql: """
      CREATE TABLE IF NOT EXISTS transcript_metadata (
        transcript_id TEXT PRIMARY KEY NOT NULL REFERENCES transcripts(id) ON DELETE CASCADE,
        project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        topics TEXT NOT NULL CHECK(json_valid(topics)),
        confidence REAL NOT NULL,
        may_contain_hallucinations INTEGER NOT NULL DEFAULT 0,
        needs_review INTEGER NOT NULL DEFAULT 0,
        generated_at INTEGER NOT NULL,
        model TEXT NOT NULL,
        prompt_version INTEGER NOT NULL,
        generator_version INTEGER NOT NULL,
        transcript_sha256 TEXT NOT NULL,
        message_count INTEGER NOT NULL,
        strategy TEXT NOT NULL CHECK(strategy IN ('full','bookends','heuristic')),
        llm_calls INTEGER NOT NULL,
        latency_ms INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    """)
    try db.create(index: "idx_tm_project", on: "transcript_metadata", columns: ["project_id"], ifNotExists: true)
    try db.create(index: "idx_tm_generated_at", on: "transcript_metadata", columns: ["generated_at"], ifNotExists: true)
    try db.create(index: "idx_tm_needs_review", on: "transcript_metadata", columns: ["needs_review", "generated_at"], ifNotExists: true)
    try db.create(index: "idx_tm_sha", on: "transcript_metadata", columns: ["transcript_sha256"], ifNotExists: true)

    // Parse errors table
    try db.create(table: "parse_errors", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull().references("transcripts", onDelete: .cascade)
      t.column("line_number", .integer).notNull()
      t.column("raw_line", .text).notNull()
      t.column("error_message", .text).notNull()
      t.column("created_at", .integer).notNull()
    }
    try db.create(index: "idx_parse_errors_transcript", on: "parse_errors", columns: ["transcript_id", "created_at"], ifNotExists: true)

    // v7: Metadata tables
    try db.create(table: "file_snapshots") { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull()
        .references("transcripts", onDelete: .cascade, onUpdate: .cascade)
      t.column("message_id", .text).notNull()
      t.column("snapshot_timestamp", .integer).notNull()
      t.column("is_snapshot_update", .integer).notNull()
      t.column("created_at", .integer).notNull()
    }
    try db.create(index: "idx_snapshots_transcript", on: "file_snapshots", columns: ["transcript_id"])
    try db.create(index: "idx_snapshots_message", on: "file_snapshots", columns: ["message_id"])
    try db.create(index: "idx_snapshots_timestamp", on: "file_snapshots", columns: ["snapshot_timestamp"])

    try db.create(table: "tracked_files") { t in
      t.column("id", .text).primaryKey()
      t.column("snapshot_id", .text).notNull()
        .references("file_snapshots", onDelete: .cascade, onUpdate: .cascade)
      t.column("file_path", .text).notNull()
      t.column("backup_filename", .text)
      t.column("version", .integer).notNull()
      t.column("backup_time", .integer).notNull()
    }
    try db.create(index: "idx_tracked_snapshot", on: "tracked_files", columns: ["snapshot_id"])
    try db.create(index: "idx_tracked_path", on: "tracked_files", columns: ["file_path"])

    try db.create(table: "transcript_summaries") { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull()
        .references("transcripts", onDelete: .cascade, onUpdate: .cascade)
      t.column("summary", .text).notNull()
      t.column("leaf_uuid", .text)
      t.column("cwd", .text)
      t.column("created_at", .integer).notNull()
    }
    try db.create(index: "idx_summaries_transcript", on: "transcript_summaries", columns: ["transcript_id"])

    try db.create(table: "system_events") { t in
      t.column("id", .text).primaryKey()
      t.column("transcript_id", .text).notNull()
        .references("transcripts", onDelete: .cascade, onUpdate: .cascade)
      t.column("timestamp", .integer).notNull()
      t.column("subtype", .text).notNull()
      t.column("level", .text).notNull()
      t.column("content", .text)
      t.column("error", .text)
      t.column("retry_attempt", .integer)
      t.column("max_retries", .integer)
      t.column("retry_in_ms", .integer)
      t.column("parent_uuid", .text)
      t.column("logical_parent_uuid", .text)
      t.column("compact_metadata", .text)
      t.column("created_at", .integer).notNull()
    }
    try db.create(index: "idx_events_transcript", on: "system_events", columns: ["transcript_id"])
    try db.create(index: "idx_events_subtype", on: "system_events", columns: ["subtype"])
    try db.create(index: "idx_events_timestamp", on: "system_events", columns: ["timestamp"])

    // v7/v11: Assistant usage table (v11: composite PK, v14: request_id normalization)
    try db.execute(sql: """
      CREATE TABLE IF NOT EXISTS assistant_usage (
        entry_id TEXT NOT NULL REFERENCES transcript_entries(id) ON DELETE CASCADE,
        request_id TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
        cache_read_tokens INTEGER NOT NULL DEFAULT 0,
        service_tier TEXT,
        ephemeral_5m_tokens INTEGER NOT NULL DEFAULT 0,
        ephemeral_1h_tokens INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entry_id, request_id)
      )
    """)
    try db.create(index: "idx_usage_entry", on: "assistant_usage", columns: ["entry_id"])
    try db.create(index: "idx_usage_model", on: "assistant_usage", columns: ["model"])

    // v10/v11: Staging table for FK-safe assistant_usage inserts
    try db.execute(sql: """
      CREATE TABLE IF NOT EXISTS assistant_usage_pending (
        entry_id TEXT NOT NULL,
        request_id TEXT NOT NULL,
        model TEXT NOT NULL,
        input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        cache_creation_tokens INTEGER NOT NULL DEFAULT 0,
        cache_read_tokens INTEGER NOT NULL DEFAULT 0,
        service_tier TEXT,
        ephemeral_5m_tokens INTEGER NOT NULL DEFAULT 0,
        ephemeral_1h_tokens INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER))
      )
    """)
    // v15: Composite index for pending lookups
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_pending_entry_request
      ON assistant_usage_pending(entry_id, request_id)
    """)
    try db.create(index: "idx_pending_created", on: "assistant_usage_pending", columns: ["created_at"])

    // v11: BEFORE INSERT trigger for FK safety net (staging behavior)
    try db.execute(sql: """
      CREATE TRIGGER IF NOT EXISTS trg_assistant_usage_stage
      BEFORE INSERT ON assistant_usage
      FOR EACH ROW
      WHEN NOT EXISTS (SELECT 1 FROM transcript_entries WHERE id = NEW.entry_id)
      BEGIN
        INSERT OR REPLACE INTO assistant_usage_pending (
          entry_id, request_id, model, input_tokens, output_tokens,
          cache_creation_tokens, cache_read_tokens, service_tier,
          ephemeral_5m_tokens, ephemeral_1h_tokens
        ) VALUES (
          NEW.entry_id,
          COALESCE(NULLIF(NEW.request_id,''), NEW.entry_id),
          NEW.model, NEW.input_tokens, NEW.output_tokens,
          COALESCE(NEW.cache_creation_tokens,0), COALESCE(NEW.cache_read_tokens,0),
          NEW.service_tier,
          COALESCE(NEW.ephemeral_5m_tokens,0), COALESCE(NEW.ephemeral_1h_tokens,0)
        );
        SELECT RAISE(IGNORE);
      END
    """)

    // v8: Project visits table (v12: migrated to projects.last_viewed_ts, kept for backward compat)
    try db.create(table: "project_visits", ifNotExists: true) { t in
      t.column("project_id", .text).primaryKey()
        .references("projects", onDelete: .cascade, onUpdate: .cascade)
      t.column("last_viewed_at", .text)  // ISO8601Z UTC
      t.column("last_selected_at", .text)  // ISO8601Z UTC
      t.column("pinned", .integer).notNull().defaults(to: 0)
    }

    // v13: Partial index for newly created projects (optimization)
    try db.execute(sql: """
      CREATE INDEX IF NOT EXISTS idx_projects_new
      ON projects(created_at DESC)
      WHERE last_viewed_ts = 0.0
    """)

    // Run ANALYZE to update statistics
    try db.execute(sql: "ANALYZE")
  }
}

// MARK: - Database Extension for Migration Safety

private extension Database {
  /// Check if a column exists in a table
  /// Used by migrations to avoid "duplicate column" errors on clean installs
  func columnExists(_ column: String, in table: String) throws -> Bool {
    // Validate table name to prevent SQL injection (PRAGMA doesn't support bound parameters)
    // SQLite identifiers: alphanumeric, underscore, must not start with digit (unless quoted)
    let validTableName = table.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    guard validTableName, !table.isEmpty else {
      throw DatabaseError(message: "Invalid table name: \(table)")
    }

    // Use string interpolation for table name (PRAGMA doesn't support bound parameters)
    // Keep bound parameter for column name
    let sql = "SELECT 1 FROM pragma_table_info('\(table)') WHERE name = ?"
    return try Int.fetchOne(self, sql: sql, arguments: [column]) != nil
  }
}
