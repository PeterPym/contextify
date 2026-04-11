### Added
- Menu bar mode with branded Contextify icon, background utility operation, and popover quick-access panel
- Contextify Cloud sync: push and pull transcripts across devices with per-project sync controls, progress tracking, and ETA estimation
- Launch at Login support via General settings tab, with first-run prompt (DMG) and onboarding step (App Store)
- Device provenance: transcript entries now record which machine created them
- Database write coordinator for safe concurrent ingest and cloud sync
- Porter stemming search index for better natural-language query matching
- Transcript tags for excluding benchmarks and evaluations from search results
- Git-anchored search: find conversations by the files they touched
- CLI `cloud` commands available directly from the macOS CLI
- CLI `--anchor-files` flag for AI-driven git-accelerated retrieval
- CLI `--hours` flag and automatic time-scoped intent detection
- CLI `--project` name-based lookup with fuzzy suggestions on no-match
- CLI short UUID prefix support for entry and context commands
- CLI search scope summary showing entry, project, and device counts
- CLI data freshness indicator in status output
- FTS5 hyphen pre-processing for queries like "pre-commit" or "e2e"
- Proof-of-concept parsers for Gemini CLI and OpenCode transcript formats
- Sidechain transcript discovery (subagents/ subdirectories)

### Changed
- Cloud push batch size increased from 500 to 2500 for faster sync
- Settings window reorganized: new General tab, improved Database and CLI tab layouts
- CLI shim suppresses multi-install warning for non-TTY callers (scripts, pipes)

### Fixed
- Cloud sync chunks large queries to stay under SQLite's 999-parameter limit
- Cloud sync retries automatically on transient 502/503/504 server errors
- Cloud sync preserves nested JSON in tool invocation metadata
- Cloud sync handles duplicate transcripts when local ingest races with pull
- Cloud sync normalizes device IDs and repo origin URL variants
- Cloud sync defers gracefully when ingest is in progress instead of failing
- Orphaned stalled server sessions no longer pollute sync status display
- Search queries with parentheses and unbalanced quotes handled correctly
- Porter stemming applies only to simple tokens, preserving phrase queries
- CLI escapes LIKE wildcards in prefix resolver, fixing underscore and percent in project names
- Settings window stays above main window when Keep on Top is enabled
- Custom project title: missing key is now a no-op instead of clearing the title
- Startup follow-up alerts no longer chain on top of each other
