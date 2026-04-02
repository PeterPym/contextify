# Changelog

All notable changes to Contextify will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Changed
- **CLI search text output** - Human-readable format now shows entry IDs, human dates, project summary, and drill-down hints instead of raw timestamps and scores
- **Total Recall SKILL.md** - Text-first approach: canonical search commands no longer use `--json` by default. Added CRITICAL anti-piping guardrails. Restored `--hours`, `--exclude-tags`, `--device` flag documentation.

## [1.3.1] - 2026-02-18

### Added
- **Always-on-Top Window** - HUD can float above all windows, including full-screen spaces
  - Toggle via Window menu or standard macOS keyboard shortcut
  - Stays visible on focus loss, joins all Spaces
- **CLI Search Improvements** - More powerful Total Recall queries
  - `--offset` pagination for large result sets
  - `--snippet-tokens` parameter to control search snippet length
  - `--count-only` flag for fast result counting without returning entries
  - Per-term match counts for OR search queries
  - `totalCount` field in search metadata
  - Hardened OR term parsing
- **Total Recall Skill Enhancements** - Smarter query handling for AI agents
  - Query expansion and intent classification
  - JSON schema documentation and examples in SKILL.md

### Changed
- CLI help text now shows `contextify` binary name instead of `swift run contextify-query`

### Fixed
- CLI now warns when `--project` is used on the `context` command (unsupported flag)
- Corrected sync config field name and enabled bidirectional sync
- Total Recall SKILL.md error envelope and query guidance corrections
- Duplicate Window menu item removed (use CommandGroup)

## [1.3.0] - 2026-01-25

(DMG + Linux CLI release; no App Store submission)

### Added
- **Unified CLI Binary** - Single `contextify` command replaces separate `contextify-query` and `contextify-ingest` binaries, with backwards-compatible symlinks
- **Tab Grouping** - Organize project tabs into named groups
  - Automatic worktree-based grouping detects git worktree siblings
  - Manual grouping for non-worktree projects via context menu
  - Group rename, color assignment from palette, and color change via context menu
  - Hover tooltip overlay showing group name
  - Context-aware keyboard shortcuts with shortcut hints in menus
  - Group and within-group reorder operations persist across sessions
- **Codex Global Discovery** - Contextify scans `~/.codex/sessions` to index Codex-only projects
  - Security-scoped enumeration with cached `CodexIndex` snapshots
  - Codex-only projects appear in Welcome modal, ProjectSwitcher, and status bar with provider badges
  - Fast-path/primer pipelines ingest Codex transcripts without requiring `.codex` folders inside each project
- **Timeline Improvements** - Enhanced conversation timeline with provider branding and session management
  - Provider-specific icons for assistant messages (Claude Code: orange, Codex CLI: blue)
  - Timeline entries persist when switching between conversation sessions
  - Session type detection (new vs existing conversations)
  - Reveal-in-inventory action on system messages with clickable button
  - Inline image rendering with Quick Look style preview
  - Markdown table rendering in expanded detail view
  - Model chip on agent spawn badges
  - Template summaries for Contextify tool entries
- **Linux CLI (Total Recall)** - Full query and ingest support on Linux
  - Unified contextify binary with `search`, `context`, `activity`, `ingest`, and `doctor` commands
  - XDG-compliant paths, proper exit codes, new help system
  - systemd timer commands for automated ingestion; cron fallback when systemd unavailable
  - `curl | sh` installer with colors, interactive prompts, smart systemd detection
  - `--uninstall` flag for clean removal
  - Auto-ingest transcripts on install with progress spinner and discovery status
  - macOS DMG install path alongside Linux support
- **CLI Enhancements** - More capable query CLI on all platforms
  - `--this-worktree` and `--exclude` flags for scoped queries
  - `--input` and `--since` options for flexible ingestion
  - Worktree expansion in search and activity commands
  - Multi-project query support
  - `doctor` command for health checking
  - Repair state detection for partial installations
  - Codex skill installation support
  - Progress tracking during ingest with quiet mode support

### Changed
- **Lazy Watcher Monitoring** - Per-file watchers run on a budgeted HOT + WARM set (up to three projects) with cold activity signals; degraded mode drops to hot-only on FD exhaustion
- **Timeline Colors** - Updated timeline accent colors for better visual harmony
  - User messages: Rich blue `#4A7BA7` (professional, distinct)
  - Assistant messages: Warm gray `#9B8B7E` (brand-neutral, works with any provider)
- Provider icons appear on assistant messages instead of system messages
- System messages use generic text (removed provider-specific branding)
- DMG background updated with arrow graphic and corrected Applications icon on macOS 26

### Fixed
- Hidden project tabs now persist across app restart
- Timeline icon placement corrected to assistant messages (semantic accuracy)
- Project misattribution fixed by reassigning entries based on CWD
- LLM hallucination prevention via stateless mode and stricter validation
- O(n) syscall bottleneck removed from project path inference (discovery performance)
- SQLite busy timeout reduced to 2 seconds for CLI responsiveness
- SIGINT handled gracefully in CLI with improved progress display
- Async checkpoint writes corrected with proper await
- Task invocations now visible with meaningful content in timeline
- Stuck spinner and UI lag fixed in watcher/timeline coordination

## [1.0.7] - 2025-12-20

(DMG release - see releases/v1.0.7/ for details)

## [1.0.6] - 2025-12-14

(App Store release - see releases/v1.0.6/ for details)

## [1.0.5] - 2025-12-05

(DMG release - see releases/v1.0.5/ for details)

## [1.0.2] - 2025-11-23

(DMG release - see releases/v1.0.2/ for details)

## [1.0.1] - 2025-11-20

(Initial public release)

## [1.0.0] - 2025-11-17

Initial release of Contextify.

### Added
- **Core Timeline Monitoring** - Real-time conversation tracking
  - JSONL transcript parsing for Claude Code and Codex CLI
  - LLM-based timeline summarization with disposition classification
  - Security-scoped bookmarks for sandboxed file access
  - Real-time file watching with DispatchSource

- **Timeline Caching** - Persistent cache system for timeline summaries
  - Actor-based orchestrator for thread-safe operations
  - File-based storage in `~/Library/Application Support/Contextify/timeline-cache/`
  - Per-conversation caching with content-based invalidation
  - Dual-form tense storage (present and past forms)
  - Cache hit/miss logging with hit rate tracking

- **Timeline Tense Management** - Natural progression from active to completed state
  - Dual-form generation: present continuous and past simple
  - Instant tense conversion for completed tasks

- **Task Duration Tracking** - Show elapsed time for completed tasks
  - Duration display next to completion markers
  - Jump-to-request arrows for navigating to original directive
  - Request-to-completion correlation tracking

- **Transcripts** - Browse and switch between conversation sessions
  - Independent window UI with session list
  - Worktree support for git repositories
  - Session metadata display (provider, duration, message count)
  - Real-time session discovery and updates

- **Git Integration** - Repository and branch detection
  - Automatic git repository discovery
  - Worktree support and detection
  - Branch monitoring with file watchers
  - Sandboxed HEAD parsing and git subprocess fallback

- **Project Management** - File and URL ingestion
  - Drag-and-drop file ingestion with Markdown artifacts
  - URL ingestion and metadata extraction
  - Session and checkpoint management

- **UI Foundation** - SwiftUI HUD interface
  - Project root selector with persistence
  - Git branch display
  - Timeline view with auto-scroll
  - Toast notifications for user feedback
  - Menu bar extra for quick access
