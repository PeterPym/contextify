import Foundation
import GRDB

/// SQLite schema for Contextify transcript storage
/// Based on sql-implementation-plan-05.md
enum DatabaseSchema {
  static let version = 1

  /// Create all tables and indexes for the database
  static func migrate(_ db: Database) throws {
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
      t.column("summary", .text)
      t.column("disposition", .text)
      t.column("display_in_timeline", .integer).notNull().defaults(to: 1)
      t.column("is_completion", .integer).notNull().defaults(to: 0)
      t.column("is_directive", .integer).notNull().defaults(to: 0)
      t.column("parent_id", .text).references("transcript_entries", onDelete: .setNull)
      t.column("git_branch", .text)
      t.column("git_commit", .text)
      t.column("cwd", .text)
      t.column("created_at", .integer).notNull()
      t.column("updated_at", .integer).notNull()
    }
    try db.create(index: "idx_entries_transcript_time", on: "transcript_entries", columns: ["transcript_id", "timestamp"], ifNotExists: true)
    try db.create(index: "idx_entries_project_time", on: "transcript_entries", columns: ["project_id", "timestamp"], ifNotExists: true)
    try db.create(index: "idx_entries_project_feed", on: "transcript_entries", columns: ["project_id", "timestamp"], ifNotExists: true, condition: "display_in_timeline = 1")
    try db.create(index: "idx_entries_content_sha", on: "transcript_entries", columns: ["content_sha256"], ifNotExists: true)
    try db.create(index: "idx_entries_completion", on: "transcript_entries", columns: ["project_id", "is_completion", "timestamp"], ifNotExists: true, condition: "is_completion = 1")

    // Timeline cache table
    try db.create(table: "timeline_cache", ifNotExists: true) { t in
      t.column("content_sha256", .text).notNull()
      t.column("window_sha256", .text).notNull()
      t.column("entry_id", .text).notNull().references("transcript_entries", onDelete: .cascade)
      t.column("generator_signature", .text).notNull()
      t.column("disposition", .text).notNull()
      t.column("present_form", .text).notNull()
      t.column("past_form", .text).notNull()
      t.column("selected_form", .text).notNull().check(sql: "selected_form IN ('present','past')")
      t.column("verb_lemma", .text)
      t.column("generated_at", .integer).notNull()
      t.column("user_edited", .integer).notNull().defaults(to: 0)
      t.column("user_text", .text)
      t.column("edited_at", .integer)
      t.column("request_id", .text)
      t.column("duration", .double)

      t.primaryKey(["content_sha256", "window_sha256"])
    }
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
