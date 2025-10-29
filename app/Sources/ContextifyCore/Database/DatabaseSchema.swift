import Foundation
import GRDB

/// SQLite schema for Contextify transcript storage
/// Based on sql-implementation-plan-05.md and sql-integration-plan-v2.md
///
/// Time Unit Convention:
/// - Standard timestamps (created_at, updated_at, generated_at, timestamp, last_modified): Unix seconds (Int)
/// - High-precision timestamps (mtime_ms, latency_ms, etc): Unix milliseconds (Int64)
/// - Rationale: Seconds provide sufficient precision for most operations, milliseconds used where needed
/// - Future: Consider migrating all timestamps to milliseconds for consistency
enum DatabaseSchema {
  static let version = 16

  /// Create migrator for schema evolution
  static func createMigrator() -> DatabaseMigrator {
    var migrator = DatabaseMigrator()

    // v1: Base schema (all tables and indexes)
    migrator.registerMigration("v1_base") { db in
      try createBaseSchema(db)
    }

    // v2: Window fields for fast cache joins
    migrator.registerMigration("v2_window_sha") { db in
      try db.alter(table: "transcript_entries") { t in
        t.add(column: "prev1_id", .text)
        t.add(column: "prev2_id", .text)
        t.add(column: "window_sha256", .text)
      }
    }

    // v2: Resume checkpoint for correct window state across restarts
    migrator.registerMigration("v2_resume_checkpoint") { db in
      try db.alter(table: "transcripts") { t in
        t.add(column: "last_processed_entry_id", .text)
      }

      // Best-effort backfill: set to last chronological entry per transcript
      let tids = try String.fetchAll(db, sql: "SELECT id FROM transcripts")
      for tid in tids {
        if let lastId = try String.fetchOne(
          db,
          sql: """
            SELECT id FROM transcript_entries
            WHERE transcript_id = ?
            ORDER BY timestamp DESC, id DESC
            LIMIT 1
          """,
          arguments: [tid]
        ) {
          try db.execute(
            sql: "UPDATE transcripts SET last_processed_entry_id = ? WHERE id = ?",
            arguments: [lastId, tid]
          )
        }
      }
    }

    // v2: Backfill window fields for existing data
    migrator.registerMigration("v2_window_sha_backfill") { db in
      let tids = try String.fetchAll(db, sql: "SELECT id FROM transcripts")
      for tid in tids {
        let rows = try Row.fetchAll(db, sql: """
          SELECT id
          FROM transcript_entries
          WHERE transcript_id = ?
          ORDER BY timestamp ASC, id ASC
        """, arguments: [tid])

        var prev2: String? = nil
        var prev1: String? = nil
        for r in rows {
          let id: String = r["id"]
          let win = SHA256Utils.computeWindowSHA256(prev2: prev2, prev1: prev1)
          try db.execute(
            sql: """
              UPDATE transcript_entries
              SET prev2_id = ?, prev1_id = ?, window_sha256 = ?
              WHERE id = ?
            """,
            arguments: [prev2, prev1, win, id]
          )
          prev2 = prev1
          prev1 = id
        }
      }

      // Create covering index AFTER backfill to avoid costly index maintenance
      // Includes (timestamp, created_at, id) to match feed query ORDER BY for consistent sorting
      try db.create(
        index: "idx_entries_feed_cover",
        on: "transcript_entries",
        columns: [
          "project_id",
          "timestamp",   // Primary sort key
          "created_at",  // Secondary sort key for tie-breaking
          "id",          // Tertiary sort key for stable ordering
          "content_sha256",
          "window_sha256",
          "kind",
          "is_completion",
          "session_id"
        ],
        ifNotExists: true,
        condition: "display_in_timeline = 1"
      )

      // Run ANALYZE to update statistics after bulk operations
      try db.execute(sql: "ANALYZE")
    }

    // v3: Path normalization and freshness tracking for transcript inventory (pure DDL)
    // Backfill happens during discovery/upsert, not in migration
    migrator.registerMigration("v3_transcript_identity") { db in
      // Check if columns already exist (safe for re-running)
      let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(transcripts)")
      let columnNames = Set(tableInfo.map { $0["name"] as! String })

      // Add columns only if they don't exist
      if !columnNames.contains("normalized_path") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN normalized_path TEXT")
      }
      if !columnNames.contains("path_hash") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN path_hash TEXT")
      }
      if !columnNames.contains("content_length") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN content_length INTEGER")
      }
      if !columnNames.contains("mtime_ms") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN mtime_ms INTEGER")
      }
      if !columnNames.contains("content_sha256") {
        try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN content_sha256 TEXT")
      }

      // Backfill mtime_ms from legacy mtime_ns if present (only for databases that had the old column)
      if columnNames.contains("mtime_ns") {
        try db.execute(sql: """
          UPDATE transcripts
          SET mtime_ms = mtime_ns / 1000000
          WHERE mtime_ns IS NOT NULL AND mtime_ms IS NULL
        """)
      }

      // Create transcript_metadata table
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
          strategy TEXT NOT NULL,
          llm_calls INTEGER NOT NULL,
          latency_ms INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      """)

      // Create indexes for transcript_metadata
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_transcript_id ON transcript_metadata(transcript_id)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_project ON transcript_metadata(project_id)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_generated_at ON transcript_metadata(generated_at DESC)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_needs_review ON transcript_metadata(needs_review, generated_at DESC)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_tm_sha ON transcript_metadata(transcript_sha256)
      """)

      // Create entry indexes for cursor-based pagination (critical for performance)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_cursor
        ON transcript_entries(project_id, timestamp, created_at, id)
        WHERE display_in_timeline = 1
      """)

      // Create identity indexes immediately (don't require backfill)
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
    }

    // v4: RAG embeddings storage
    migrator.registerMigration("v4_embeddings") { db in
      // Check if columns already exist (safe for re-running)
      let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(transcript_entries)")
      let columnNames = Set(tableInfo.map { $0["name"] as! String })

      // Add embedding columns only if they don't exist
      if !columnNames.contains("embedding") {
        try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN embedding BLOB")
      }
      if !columnNames.contains("embedding_version") {
        try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN embedding_version INTEGER DEFAULT 1")
      }
      if !columnNames.contains("embedding_generated_at") {
        try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN embedding_generated_at INTEGER")
      }

      // Create index for efficient queries on embedding presence
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_embedding_version
        ON transcript_entries(embedding_version)
      """)
    }

    // v5: Backfill path_hash for transcript identity and deduplicate
    migrator.registerMigration("v5_path_hash_backfill_dedup") { db in
      // Step 1: Backfill path_hash for rows where it's NULL
      let transcriptsToBackfill = try Row.fetchAll(db, sql: """
        SELECT id, file_path
        FROM transcripts
        WHERE path_hash IS NULL OR path_hash = ''
      """)

      for row in transcriptsToBackfill {
        let transcriptId: String = row["id"]
        let filePath: String = row["file_path"]

        // Compute normalized path and hash
        let (normalizedPath, pathHash) = PathNormalizer.normalizeAndHash(filePath)

        // Update the transcript
        try db.execute(sql: """
          UPDATE transcripts
          SET normalized_path = ?, path_hash = ?
          WHERE id = ?
        """, arguments: [normalizedPath, pathHash, transcriptId])
      }

      // Step 2: Deduplicate transcripts with same (provider, path_hash)
      // Find groups of duplicate transcripts
      let duplicateGroups = try Row.fetchAll(db, sql: """
        SELECT provider, path_hash, COUNT(*) as count
        FROM transcripts
        WHERE path_hash IS NOT NULL AND path_hash <> ''
          AND (provider_session_id IS NULL OR provider_session_id = '')
        GROUP BY provider, path_hash
        HAVING count > 1
      """)

      for group in duplicateGroups {
        let provider: String = group["provider"]
        let pathHash: String = group["path_hash"]

        // Get all transcripts in this duplicate group, ordered by created_at (oldest first)
        let duplicates = try Row.fetchAll(db, sql: """
          SELECT id, created_at
          FROM transcripts
          WHERE provider = ? AND path_hash = ?
            AND (provider_session_id IS NULL OR provider_session_id = '')
          ORDER BY created_at ASC
        """, arguments: [provider, pathHash])

        guard duplicates.count > 1 else { continue }

        // Keep the oldest transcript (first in list)
        let keeperId: String = duplicates[0]["id"]
        let duplicateIds = duplicates.dropFirst().map { $0["id"] as! String }

        // Reassign entries from duplicates to the keeper
        for dupId in duplicateIds {
          try db.execute(sql: """
            UPDATE transcript_entries
            SET transcript_id = ?
            WHERE transcript_id = ?
          """, arguments: [keeperId, dupId])

          // Delete the duplicate transcript
          try db.execute(sql: """
            DELETE FROM transcripts
            WHERE id = ?
          """, arguments: [dupId])
        }
      }

      // Run ANALYZE to update statistics after bulk operations
      try db.execute(sql: "ANALYZE")
    }

    // v6: Remove denormalized fields (summary, disposition, is_completion, is_directive)
    migrator.registerMigration("v6_remove_denormalized_fields") { db in
      // SQLite doesn't support DROP COLUMN, so we need to recreate the table

      // 1. Create new table without denormalized fields
      try db.create(table: "transcript_entries_new") { t in
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
        t.column("prev1_id", .text)
        t.column("prev2_id", .text)
        t.column("window_sha256", .text)
        t.column("embedding", .blob)
        t.column("embedding_version", .integer).defaults(to: 1)
        t.column("embedding_generated_at", .integer)
      }

      // 2. Copy data from old table (excluding removed columns)
      try db.execute(sql: """
        INSERT INTO transcript_entries_new
        SELECT id, transcript_id, project_id, session_id, provider, kind,
               timestamp, content, content_sha256, display_in_timeline,
               parent_id, git_branch, git_commit, cwd, created_at, updated_at,
               prev1_id, prev2_id, window_sha256, embedding, embedding_version,
               embedding_generated_at
        FROM transcript_entries
      """)

      // 3. Drop old table
      try db.drop(table: "transcript_entries")

      // 4. Rename new table
      try db.rename(table: "transcript_entries_new", to: "transcript_entries")

      // 5. Recreate all indexes
      try db.create(index: "idx_entries_transcript_time", on: "transcript_entries",
                    columns: ["transcript_id", "timestamp"], ifNotExists: true)
      try db.create(index: "idx_entries_content_sha", on: "transcript_entries",
                    columns: ["content_sha256"], ifNotExists: true)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_project_time
        ON transcript_entries(project_id, timestamp DESC)
      """)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_project_feed
        ON transcript_entries(project_id, timestamp DESC)
        WHERE display_in_timeline = 1
      """)

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // MARK: v7 Migration: Add Metadata Tables
    migrator.registerMigration("v7_add_metadata_tables") { db in
      // Create file_snapshots table
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

      // Create tracked_files table
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

      // Create transcript_summaries table
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

      // Create system_events table
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

      // Create assistant_usage table
      try db.create(table: "assistant_usage") { t in
        t.column("entry_id", .text).primaryKey()
          .references("transcript_entries", onDelete: .cascade, onUpdate: .cascade)
        t.column("request_id", .text)
        t.column("model", .text).notNull()
        t.column("input_tokens", .integer).notNull()
        t.column("output_tokens", .integer).notNull()
        t.column("cache_creation_tokens", .integer).notNull()
        t.column("cache_read_tokens", .integer).notNull()
        t.column("service_tier", .text)
        t.column("ephemeral_5m_tokens", .integer)
        t.column("ephemeral_1h_tokens", .integer)
      }

      try db.create(index: "idx_usage_model", on: "assistant_usage", columns: ["model"])

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // MARK: v8 Migration: Add project_visits table for multi-project switcher
    migrator.registerMigration("v8_project_visits") { db in
      // Create project_visits table
      try db.create(table: "project_visits") { t in
        t.column("project_id", .text).primaryKey()
          .references("projects", onDelete: .cascade)
        t.column("last_viewed_at", .text)  // ISO8601Z UTC (NULL = never viewed, all entries unread)
        t.column("last_selected_at", .text)  // ISO8601Z UTC (last time user switched to this project)
        t.column("pinned", .integer).notNull().defaults(to: 0)
          .check(sql: "pinned IN (0,1)")
      }

      // Create indices for unread calculation (critical for performance)
      // These support the JOIN query: entries → transcripts → project_visits

      // Index on transcript_entries for efficient JOIN on transcript_id + sorting by created_at
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_transcript_entries_transcript_created
        ON transcript_entries(transcript_id, created_at)
      """)

      // Index on transcripts for efficient JOIN on project_id
      // (may already exist from base schema, but add IF NOT EXISTS for safety)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_transcripts_project_id
        ON transcripts(project_id)
      """)

      // Optional: backfill current project only (others default to NULL = all unread)
      // Get current project from HUDViewModel if available
      // Note: This is best-effort; new projects will start with NULL (all unread)

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // v9: Additional indices for unread count performance
    migrator.registerMigration("v9_unread_indices") { db in
      // Index on project_visits for efficient filtering by last_viewed_at
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_project_visits_last_viewed
        ON project_visits(project_id, last_viewed_at)
      """)

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // v10: Staging table for assistant_usage when entries arrive out-of-order
    migrator.registerMigration("v10_assistant_usage_staging") { db in
      // Staging table for usage records that arrive before their entries
      try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS assistant_usage_pending (
          entry_id TEXT NOT NULL,
          request_id TEXT NOT NULL,
          model TEXT,
          input_tokens INTEGER,
          output_tokens INTEGER,
          cache_creation_tokens INTEGER,
          cache_read_tokens INTEGER,
          service_tier TEXT,
          ephemeral_5m_tokens INTEGER,
          ephemeral_1h_tokens INTEGER,
          PRIMARY KEY (entry_id, request_id)
        )
      """)

      // Index for efficient reconciliation lookups
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_ausage_pending_entry
        ON assistant_usage_pending(entry_id)
      """)

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    // v11: Harden assistant_usage with composite PK, created_at, and safety trigger
    migrator.registerMigration("v11_assistant_usage_hardening") { db in
      // 1. Add created_at to staging table for pruning stale records
      try db.execute(sql: """
        ALTER TABLE assistant_usage_pending
        ADD COLUMN created_at TEXT DEFAULT CURRENT_TIMESTAMP
      """)

      // 2. Rebuild assistant_usage with composite PRIMARY KEY (entry_id, request_id)
      //    This allows multiple usage records per entry (e.g., retries, streaming)
      try db.execute(sql: """
        CREATE TABLE assistant_usage_new (
          entry_id TEXT NOT NULL,
          request_id TEXT NOT NULL,
          model TEXT NOT NULL,
          input_tokens INTEGER NOT NULL,
          output_tokens INTEGER NOT NULL,
          cache_creation_tokens INTEGER NOT NULL,
          cache_read_tokens INTEGER NOT NULL,
          service_tier TEXT,
          ephemeral_5m_tokens INTEGER,
          ephemeral_1h_tokens INTEGER,
          PRIMARY KEY (entry_id, request_id),
          FOREIGN KEY (entry_id) REFERENCES transcript_entries(id) ON DELETE CASCADE
        )
      """)

      // Copy existing data (dedup by entry_id, request_id)
      try db.execute(sql: """
        INSERT OR IGNORE INTO assistant_usage_new
        SELECT * FROM assistant_usage
      """)

      // Swap tables
      try db.execute(sql: "DROP TABLE assistant_usage")
      try db.execute(sql: "ALTER TABLE assistant_usage_new RENAME TO assistant_usage")

      // Recreate index
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_usage_model
        ON assistant_usage(model)
      """)

      // 3. Add BEFORE INSERT trigger to auto-stage unsafe writes
      //    Any direct insert that violates FK gets staged instead of crashing
      try db.execute(sql: """
        CREATE TRIGGER IF NOT EXISTS trg_assistant_usage_stage
        BEFORE INSERT ON assistant_usage
        WHEN NOT EXISTS (SELECT 1 FROM transcript_entries WHERE id = NEW.entry_id)
        BEGIN
          INSERT OR REPLACE INTO assistant_usage_pending (
            entry_id, request_id, model, input_tokens, output_tokens,
            cache_creation_tokens, cache_read_tokens, service_tier,
            ephemeral_5m_tokens, ephemeral_1h_tokens, created_at
          ) VALUES (
            NEW.entry_id, NEW.request_id, NEW.model, NEW.input_tokens, NEW.output_tokens,
            NEW.cache_creation_tokens, NEW.cache_read_tokens, NEW.service_tier,
            NEW.ephemeral_5m_tokens, NEW.ephemeral_1h_tokens, CURRENT_TIMESTAMP
          );
          SELECT RAISE(IGNORE);
        END
      """)

      // 4. One-time cleanup: remove orphaned usage records
      try db.execute(sql: """
        DELETE FROM assistant_usage
        WHERE entry_id NOT IN (SELECT id FROM transcript_entries)
      """)

      // Run ANALYZE
      try db.execute(sql: "ANALYZE")
    }

    // v12: Epoch timestamps for unread tracking
    migrator.registerMigration("v12_epoch_timestamps") { db in
      // Add epoch timestamp columns
      try db.execute(sql: "ALTER TABLE projects ADD COLUMN last_viewed_ts REAL NOT NULL DEFAULT 0")
      try db.execute(sql: "ALTER TABLE transcript_entries ADD COLUMN created_ts REAL")

      // Backfill created_ts from existing timestamp field (Unix seconds Int -> REAL)
      try db.execute(sql: """
        UPDATE transcript_entries
        SET created_ts = CAST(timestamp AS REAL)
        WHERE created_ts IS NULL
      """)

      // Create indices for performance
      try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_projects_last_viewed_ts ON projects(last_viewed_ts)")
      // Note: Full index on created_ts removed in v13 (replaced by partial index)

      // Run ANALYZE
      try db.execute(sql: "ANALYZE")
    }

    // v13: Optimizations and backfills for unread tracking
    migrator.registerMigration("v13_unread_optimizations") { db in
      // 1. Drop redundant full index (replaced by partial index)
      try db.execute(sql: "DROP INDEX IF EXISTS idx_entries_created_ts")

      // 2. Add partial index for unread queries (display_in_timeline = 1 only)
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_transcript_created_ts_timeline
        ON transcript_entries(transcript_id, created_ts)
        WHERE display_in_timeline = 1
      """)

      // 3. Backfill projects.last_viewed_ts from project_visits.last_viewed_at (pure SQL)
      try db.execute(sql: """
        UPDATE projects
        SET last_viewed_ts = MAX(
          COALESCE(last_viewed_ts, 0),
          COALESCE((
            SELECT MAX(strftime('%s', pv.last_viewed_at))
            FROM project_visits pv
            WHERE pv.project_id = projects.id
              AND pv.last_viewed_at IS NOT NULL AND pv.last_viewed_at <> ''
          ), 0)
        )
      """)

      // Run ANALYZE
      try db.execute(sql: "ANALYZE")
    }

    // v14: Normalize assistant_usage and add reconciliation indexes
    migrator.registerMigration("v14_assistant_usage_normalization") { db in
      // 1. Normalize NULL/empty request_id values (fallback to entry_id)
      try db.execute(sql: """
        UPDATE assistant_usage SET request_id = entry_id
        WHERE request_id IS NULL OR request_id = ''
      """)

      // Also normalize in pending table
      try db.execute(sql: """
        UPDATE assistant_usage_pending SET request_id = entry_id
        WHERE request_id IS NULL OR request_id = ''
      """)

      // 2. Enforce composite PK uniqueness
      try db.execute(sql: """
        CREATE UNIQUE INDEX IF NOT EXISTS ux_assistant_usage_entry_request
        ON assistant_usage(entry_id, request_id)
      """)

      // 3. Add indexes for efficient reconciliation
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_assistant_usage_pending_entry
        ON assistant_usage_pending(entry_id)
      """)

      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_assistant_usage_entry_request
        ON assistant_usage(entry_id, request_id)
      """)
    }

    // v15: Final index cleanup and reconciliation hardening
    migrator.registerMigration("v15_index_cleanup") { db in
      // 1. Drop redundant non-unique index (unique index already exists)
      try db.execute(sql: "DROP INDEX IF EXISTS idx_assistant_usage_entry_request")

      // 2. Add composite index on pending table for efficient cleanup
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_assistant_usage_pending_entry_request
        ON assistant_usage_pending(entry_id, request_id)
      """)
    }

    // v16: Add index for unread count queries (GROUP BY project_id optimization)
    migrator.registerMigration("v16_unread_query_index") { db in
      // Index for efficient unread count queries (supports JOIN + GROUP BY + WHERE)
      // Query pattern: FROM transcript_entries WHERE display_in_timeline = 1 AND created_ts > threshold GROUP BY project_id
      try db.execute(sql: """
        CREATE INDEX IF NOT EXISTS idx_entries_unread_join
        ON transcript_entries(project_id, created_ts)
        WHERE display_in_timeline = 1
      """)

      // Run ANALYZE to update statistics
      try db.execute(sql: "ANALYZE")
    }

    return migrator
  }

  /// Create all tables and indexes for the database (v1 base schema)
  private static func createBaseSchema(_ db: Database) throws {
    try db.execute(sql: "PRAGMA foreign_keys = ON")
    try db.execute(sql: "PRAGMA journal_mode = WAL")

    // Projects table
    try db.create(table: "projects", ifNotExists: true) { t in
      t.column("id", .text).primaryKey()
      t.column("name", .text)
      t.column("root_path", .text).notNull()
      t.column("root_bookmark", .blob)
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_projects_root_path", on: "projects", columns: ["root_path"], unique: true, ifNotExists: true)

    // Transcripts table
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
      // Ingestion state
      t.column("last_processed_line", .integer).notNull().defaults(to: 0)
      t.column("parser_version", .integer).notNull().defaults(to: 1)
      t.column("status", .text).notNull().defaults(to: "active").check(sql: "status IN ('active','unavailable','error')")
      t.column("last_error", .text)
      // Bookkeeping
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()

      t.uniqueKey(["project_id", "file_path"])
    }
    try db.create(index: "idx_transcripts_project", on: "transcripts", columns: ["project_id", "updated_at"], ifNotExists: true)
    try db.create(index: "idx_transcripts_status", on: "transcripts", columns: ["status"], ifNotExists: true, condition: "status != 'active'")
    try db.create(index: "idx_transcripts_provider_session", on: "transcripts", columns: ["provider_session_id"], ifNotExists: true, condition: "provider_session_id IS NOT NULL")

    // Transcript entries table
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

    // Transcript metadata table
    try db.create(table: "transcript_metadata", ifNotExists: true) { t in
      t.column("transcript_id", .text).primaryKey().references("transcripts", onDelete: .cascade)
      t.column("project_id", .text).notNull().references("projects", onDelete: .cascade)
      t.column("title", .text).notNull()
      t.column("description", .text).notNull()
      t.column("topics", .text).notNull().check(sql: "json_valid(topics)")
      t.column("confidence", .double).notNull()
      t.column("may_contain_hallucinations", .integer).notNull().defaults(to: 0)
      t.column("needs_review", .integer).notNull().defaults(to: 0)
      t.column("generated_at", .integer).notNull()
      t.column("model", .text).notNull()
      t.column("prompt_version", .integer).notNull()
      t.column("generator_version", .integer).notNull()
      t.column("transcript_sha256", .text).notNull()
      t.column("message_count", .integer).notNull()
      t.column("strategy", .text).notNull().check(sql: "strategy IN ('full','bookends','heuristic')")
      t.column("llm_calls", .integer).notNull()
      t.column("latency_ms", .integer).notNull()
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_tmeta_project", on: "transcript_metadata", columns: ["project_id"], ifNotExists: true)
    try db.create(index: "idx_tmeta_needs_review", on: "transcript_metadata", columns: ["needs_review"], ifNotExists: true, condition: "needs_review = 1")
    try db.create(index: "idx_tmeta_prompt_ver", on: "transcript_metadata", columns: ["prompt_version"], ifNotExists: true)
    try db.create(index: "idx_tmeta_gen_ver", on: "transcript_metadata", columns: ["generator_version"], ifNotExists: true)

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
  }
}
