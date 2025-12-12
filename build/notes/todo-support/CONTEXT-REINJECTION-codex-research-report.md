---
todo_id: P1-CONTEXT-REINJECTION
title: Codex Research Report - Database Integration Architecture
type: investigation
date: 2025-12-05
status: active
description: Codex CLI response to database integration research prompt
source: Codex CLI session using P1-CONTEXT-REINJECTION-cli-research-prompt.md
related:
  - P3-RESTORE-HTTP-API
  - P1-CONTEXT-REINJECTION-cli-research-prompt.md
---

# 1. Executive Summary

Contextify already normalizes Claude Code and Codex CLI timelines into SQLite with indexes, summaries, and FTS (v29). AI coding assistants should consume that database rather than re-reading JSONL. The most practical, secure, and maintainable path is a **read-only query surface built once and consumed via two transports**:

- **Primary transport (Claude Code-first):** a **Contextify-hosted stdio MCP server** exposing high-level query tools (project feed, per-file history, transcript metadata, search) with schema/capability negotiation. No open ports; process lifetime tied to client requests.
- **Parity + fallback transport (Claude Code + Codex CLI):** a **`contextify-query` companion CLI** that uses the same query layer and discovery logic, returns JSON, and can be called from shell tools. This also serves as the escape hatch when MCP is unavailable or the app is not running.
- **Discovery contract:** a small, machine-readable **state file** plus preferences lookup for database path, schema version, build flavor (DMG/App Store), and capabilities. Assistants read this instead of guessing paths.

**Short-term (MVP):** ship the companion CLI + discovery file, documented query presets, and a Claude Code skill that biases the assistant to use the CLI over raw transcript scanning. Keep everything read-only, use WAL-safe access, and handle missing/moved DBs gracefully.

**Long-term (ideal):** layer on the stdio MCP server that reuses the CLI's query core, adds capability negotiation (schema/version), richer search (FTS), and optional subagent orchestration. REST is optional and generally unnecessary; raw SQL docs remain a fallback only. Instrument adoption (queries vs fallbacks, error rates) with local-only, non-content logs.

This stack is maintainable by a solo developer because the query logic is centralized, transport layers are thin, and the discovery file insulates callers from schema and location churn. It also respects sandbox constraints: App Store builds read/write the discovery file inside the container and expose read-only queries; DMG builds use the same contract without sandboxing.

# 2. Detailed Evaluation Matrix

| Criterion | MCP Server (stdio) | REST localhost | CLI Companion | Raw SQL Docs | Skill Definition | Subagent |
| --- | --- | --- | --- | --- | --- | --- |
| Implementation complexity | Medium: small GRDB-backed tool host + capability manifest; reuse query core | Medium-high: HTTP stack, port mgmt, auth; more QA | Low-medium: single binary/script, flags; reuse query core | Low now, high later due to fragility; docs heavy | Low: mainly metadata + references to tools/CLI | Medium-high: orchestration + routing; depends on tool layer |
| Reliability & errors | Strong: process-per-session; can gate on schema version, lock handling, WAL reads | More surface: port conflicts, sandbox issues, long-lived server errors | High: short-lived, clear exit codes; easy retries | Weak: assistants can break on schema drift; destructive queries risk | Depends on tools; helps steer usage but not execution | Depends on underlying tools; adds delegation failure modes |
| Query expressiveness | High: structured tools, FTS, canned analytics | High if implemented; similar to MCP | Medium-high: presets; harder to stream large payloads | High (raw SQL) but brittle; risky | Encodes recommended patterns; no execution power alone | High once bound to MCP/CLI; can embed playbooks |
| Performance | Low latency stdio; no serialization overhead beyond JSON | Good but adds HTTP framing; potential CORS irrelevant | Good; SQLite directly; minimal overhead | Best-path direct SQLite but error-prone; no caching help | N/A (guidance only) | Adds some routing overhead; depends on tool latency |
| Security & privacy | No open port; constrained tools; read-only DB handles | Localhost port exposure; must ensure loopback-only and auth | Read-only binary; respects file perms; no listener | Risk of accidental writes unless enforced; assistants can exfiltrate paths | Improves intent but not enforcement | Depends on tools; can restrict to read-only tools |
| Schema evolution | Capability negotiation via tool metadata; reject incompatible versions | Requires version headers and error codes; more bespoke | CLI checks schema_version, prints compatibility hints | None; assistants must track schema; likely breakage | Can describe versioned patterns but relies on tools | Delegates to tools; can encode policy |
| Degraded operation | If app absent, CLI fallback; server can report unavailable DB with actionable error | Server down/port blocked → fallback to CLI/raw | Works offline; if DB missing, emits structured error | Assistant guesses paths; likely noisy failures | Encourages fallback order in prompts | Can trigger fallback sequencing |
| Compatibility / adoption | Claude Code MCP-native; Codex CLI can also speak MCP (experimental) | Works for both if HTTP allowed; App Store sandbox friction | Works for both via shell; highest immediate adoption | Available to both but risky; assistants may avoid | Improves tool selection bias | Helps bias; currently emerging support |
| User setup cost | Add MCP server entry (per Claude Code docs); app bundles server | User must trust localhost API; possible firewall prompts | Install binary or let app drop it in PATH; zero config if discovery file exists | None beyond docs; must install sqlite3 | Minimal: add skill manifest pointing to tools | Requires enabling subagent feature; config |
| Developer cost | Build thin server + shared query lib; maintain manifest | Build/maintain HTTP server, auth, cors tests | Build CLI + discovery writer; maintain presets | Maintain schema docs; handle breakage reports | Maintain skill text + versioned references | Maintain orchestration logic; depends on tool maturity |
| Assistant engagement cost | Low: tools discoverable, high signal | Medium: assistants sometimes ignore localhost APIs | Low: shell tools are often used; simple | High risk of being ignored after breakage | Lowers risk of tool avoidance | Helps auto-select right tool once available |

# 3. Recommended Architecture & Justification

- **Core principle:** one shared, read-only query core (GRDB/SQLite) that understands schema version and capabilities. Transports (CLI, MCP) call into it; docs and skills describe it.
- **Discovery contract:** a small JSON file (e.g., `~/Library/Application Support/Contextify/state.json` for DMG; `~/Library/Containers/PeterPym.Contextify*/Data/Library/Application Support/Contextify/state.json` for App Store) containing `{ db_path, schema_version, build_flavor, last_migrated_at, capabilities[] }`. Also keep CFPreferences key `dev.contextify.customDatabaseLocation` as authoritative for custom paths. CLI/MCP resolve: (1) custom path from prefs, (2) state file, (3) default paths from DATABASE-LOCATIONS.md. If state is stale, tools emit actionable errors and fallback to find-most-recent-db heuristic.
- **Transport stack:**
  - **Companion CLI (`contextify-query`)**: ships inside app bundle and symlinked into `~/Library/Application Support/Contextify/bin`; exposes subcommands like `recent --project <id>`, `file-history --path <file>`, `search --query "..."`, `transcript --id <uuid>`, `errors`, `usage --since 7d`. JSON output; exit codes map to missing DB, schema mismatch, lock contention. Uses WAL-safe `readonly` and `immutable` flags where possible. Works whether or not the GUI app is running.
  - **MCP server (stdio)**: thin host wrapping same query functions. Tools are high-level (no arbitrary SQL). Capability negotiation: advertise `schema_version`, `fts=true`, `has_usage=true`, `build_flavor=dmg|appstore`. Reject incompatible callers with structured errors. Process lifecycle: spawned on demand by client; no listening port.
  - **Skills & subagents:** publish a Claude Code skill that prefers `contextify-query`/MCP tools for timeline/history/search questions and avoids raw transcript scanning unless DB unavailable. When subagent support is stable, define a Contextify subagent that owns these tools and is delegated timeline/history intents.
- **Security posture:** read-only queries; no network listeners; no file writes except discovery file. Respect sandbox: all file access from the app remains inside `accessProvider.withAccess()`; external tools only read the DB file the app already created (App Store container path is user-readable). No GRDB in UI; keep layering UI → VM → Orchestrator → Repo → DB.
- **Schema evolution:** bundle `schema_version` and `capabilities` in discovery file and tool metadata; tools refuse to run if DB version is higher than tool version and instruct user to update the app/CLI. Migration ownership stays in the app; tools never migrate.
- **App Store vs DMG:** same discovery contract; CLI works against container path on App Store builds. MCP server runs inside the app process (sandboxed) using stdio transport—no port binding. For DMG, either transport works directly on filesystem.

# 4. Implementation Roadmap (Phased)

**Phase 0 — Baseline / Observation**
- Ship nothing; document DB path and schema in a markdown file. Observe assistant behavior (likely keeps scanning JSONL). Go/no-go: if assistants seldom use DB or errors spike, proceed to Phase 1.

**Phase 1 — MVP (CLI + Discovery + Skill)**
- Add discovery writer (state.json) updated after migration and on path changes. Include schema_version, build_flavor, db_path, capabilities.
- Ship `contextify-query` CLI (read-only, JSON output) with 6–10 query presets and exit-code contract. Package inside app; add post-install symlink to `~/Library/Application Support/Contextify/bin` and suggest PATH entry.
- Publish Claude Code skill text pointing to the CLI (and fallback guidance). Document Codex CLI usage via shell.
- Instrument local-only logs: query counts, errors (no content). Go/no-go: adoption in logs, low error rates, no app perf regressions.

**Phase 2 — MCP Server + Capability Negotiation**
- Implement stdio MCP server that reuses CLI query core; expose same presets as tools with clear descriptions and capability metadata.
- Add schema/capability negotiation, structured errors for missing DB/locks, and timeouts.
- Update skill to prefer MCP tools when available; keep CLI fallback.
- Extend metrics: MCP vs CLI usage, error codes, fallback frequency.

**Phase 3 — Hardening & Subagent Enablement**
- Add FTS-backed search tool (project-scoped and cross-project) leveraging v28+ FTS.
- Add optional localhost REST only if needed for third-party integrations; keep disabled by default.
- When Claude Code/Codex subagents stabilize, publish a Contextify subagent that owns the MCP tools and handles timeline/history intents.
- Consider opt-in telemetry or local dashboards summarizing adoption and errors.

**Phase 4 — Optional Writes / Enrichment (future)**
- If desired, add append-only note/tag APIs with strict gating, but keep off by default. Requires schema and UX design.

Rollback: remove CLI symlink and disable MCP advertising; DB remains untouched because all tooling is read-only.

# 5. Open Questions for the App Developer

1. Is read-only sufficient for the next two releases, or should note/tag writes be planned?
2. Are we comfortable installing a helper binary into `~/Library/Application Support/Contextify/bin` and asking users to add it to PATH?
3. Should the discovery file live outside the sandbox (for easier CLI access) or stay inside the container with the CLI reading CFPreferences + fallbacks?
4. What is the acceptable latency budget per query (e.g., <150 ms for recent feed)?
5. Can the app spawn the MCP server on demand (stdio) in App Store build without extra entitlements?
6. How important is Codex CLI parity in v1 vs a Claude Code-first rollout?
7. Do we need encrypted discovery state (e.g., if DB may live in sensitive sync folders), or is plaintext path acceptable?

# 6. Effectiveness Measurement

- **Adoption metrics (local-only):** counts of CLI calls by subcommand, MCP tool invocations, error codes (missing DB, schema mismatch, lock), and fallbacks to raw file scans (detected via skill/subagent prompts).
- **Quality/UX metrics:** median/95th latency per query; success vs error ratio; structured "result empty" vs "failure" codes. If optional user feedback is available, tally "helped" vs "wrong" flags per query type.
- **Analysis cadence:** weekly rolling summaries; compare adoption before/after skill updates; A/B toggle within skill text (enable/disable DB tools) for a subset of users if feasible.
- **Privacy:** log only structured metadata (tool name, duration, error code, db_version); never log SQL, content, or paths. Keep logs local unless user opts in to share diagnostics.

# 7. Appendix

## 7.1 Schema Reference (summary)
- **projects**: project identity with `id`, `name`, `root_path`, security bookmark, `last_viewed_ts`, hidden/display_order/orphaned flags.
- **transcripts**: per transcript file metadata: `project_id`, `provider` (`claude.code`, `codex.cli`, `other`), `file_path`, provider session id, ingest state, size/mtime hashes.
- **transcript_entries**: canonical messages with `kind` (`user`/`assistant`/`system`/`summary`), timestamps, git context, window tracking, embeddings, `is_queued`.
- **timeline_cache**: derived dispositions/summaries keyed by content/window sha, with user edits and generator metadata.
- **transcript_metadata**: transcript-level titles/descriptions/topics, confidence, generator metadata, latency, `needs_review`.
- **transcript_entries_fts**: FTS5 virtual table over transcript content (user/assistant/summary) with triggers for inserts/updates/deletes.
- **assistant_usage / assistant_usage_pending**: token/cost accounting with composite PK and staging table.
- **file_snapshots / tracked_files**: file backup metadata per transcript.
- **system_events**: ingestion and command events with retry metadata.
- **parse_errors**: per-line parse failures.

## 7.2 Canonical Query Patterns (for CLI + MCP tools)
1. **Recent activity (project feed):** last N timeline entries for `project_id`, ordered by `timestamp`, `display_in_timeline=1`, joined with timeline_cache for dispositions.
2. **File history:** entries where `git_branch/git_commit` or `content` mentions a given path; include snapshots from `tracked_files`.
3. **Search (FTS):** `SELECT entry_id, snippet(...) FROM transcript_entries_fts WHERE transcript_entries_fts MATCH :q AND project_id=:pid ORDER BY rank LIMIT 50`.
4. **Session summary:** pull `transcript_metadata` and recent `timeline_cache` rows for a transcript id.
5. **Unseen since last visit:** entries with `created_ts > projects.last_viewed_ts` for a project.
6. **Queued/ongoing operations:** entries with `is_queued=1` for a session to show pending work.
7. **Error diagnostics:** recent `system_events` with level error/warning and `parse_errors` for failing transcripts.
8. **Token/cost rollup:** aggregate `assistant_usage` by day/model and by `project_id`.
9. **Topic drill-down:** `transcript_metadata.topics` JSON contains a tag; list matching transcripts with confidence/latency.
10. **Cross-project deep search:** FTS search without project filter, returning `project_id` + transcript metadata for navigation.
