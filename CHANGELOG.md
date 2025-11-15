# Changelog

All notable changes to Contextify will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Codex Global Discovery** - Contextify now scans `~/.codex/sessions` to index Codex-only projects.
  - Security-scoped enumeration with cached `CodexIndex` snapshots.
  - Codex-only projects appear in Welcome modal, ProjectSwitcher, and status bar with 🟡 provider badges.
  - Fast-path/primer pipelines ingest Codex transcripts without requiring `.codex` folders inside each project.
- **Timeline Improvements** - Enhanced conversation timeline with provider branding and session management
  - Provider-specific icons for assistant messages (Claude Code: orange, Codex CLI: blue)
  - Timeline entries now persist when switching between conversation sessions
  - Session type detection (new vs existing conversations)
  - Reveal-in-inventory action on system messages with clickable button (↗️)
  - Harmonious color palette: warm gray assistant messages, rich blue user messages
  - Custom provider icons at 12pt for subtle, professional branding
  - Universal color compatibility across all provider brands

### Changed
- **Timeline Colors** - Updated timeline accent colors for better visual harmony
  - User messages: Rich blue `#4A7BA7` (professional, distinct)
  - Assistant messages: Warm gray `#9B8B7E` (brand-neutral, works with any provider)
  - System messages: Standard gray (unchanged)
- **Icon Placement** - Provider icons now appear on assistant messages instead of system messages
- **System Messages** - Removed provider-specific branding from system message text (now generic)

### Fixed
- Timeline icon placement corrected to assistant messages (semantic accuracy)

## 2025-10-10 - Timeline Caching & Transcript Inventory

### Added
- **Transcript Inventory** - Browse and switch between conversation sessions
  - Independent window UI with session list
  - Worktree support for git repositories
  - Session metadata display (provider, duration, message count)
  - Real-time session discovery and updates
  - Click-to-switch session functionality

- **Timeline Caching** - Persistent cache system for timeline summaries
  - Actor-based orchestrator for thread-safe operations
  - File-based storage in `~/Library/Application Support/Contextify/timeline-cache/`
  - Per-conversation caching with content-based invalidation
  - Dual-form tense storage (present and past forms)
  - Cache hit/miss logging with hit rate tracking
  - Performance: 1-2 LLM calls on startup vs 20-50 previously

- **Timeline Tense Management** - Natural progression from active to completed state
  - Dual-form generation: present continuous and past simple
  - `flipTenseToPast()` method for instant tense conversion
  - No regex mutations, pure data-driven approach

- **Task Duration Tracking** - Show elapsed time for completed tasks
  - Duration display next to completion markers (e.g., "✓ Completed in 2m 34s")
  - Jump-to-request arrows for navigating to original directive
  - Request-to-completion correlation tracking

### Changed
- **Timeline Entry Filtering** - Reduced assistant entry density
  - Disposition-based filtering (suppress ack/wip, keep completion/proposal)
  - Merged sequential completion entries to reduce redundancy
  - Balanced verbosity (3-5 entries per cycle vs 10-14 previously)

### Fixed
- Timeline entry tense inconsistency (entries now use appropriate tense)
- Sequential completed entries creating redundancy

## 2025-10-08 - Initial Core Features

### Added
- **Core Timeline Monitoring** - Real-time conversation tracking
  - JSONL transcript parsing for Claude Code and Codex CLI
  - LLM-based timeline summarization with disposition classification
  - Security-scoped bookmarks for sandboxed file access
  - Real-time file watching with DispatchSource

- **Git Integration** - Repository and branch detection
  - Automatic git repository discovery
  - Worktree support and detection
  - Branch monitoring with file watchers
  - Sandboxed HEAD parsing and git subprocess fallback

- **Project Management** - File and URL ingestion
  - Drag-and-drop file ingestion with Markdown artifacts
  - URL ingestion and metadata extraction
  - Session and checkpoint management
  - Timestamped output artifacts in `~/Contextify/outputs`

- **UI Foundation** - SwiftUI HUD interface
  - Project root selector with persistence
  - Git branch display
  - Timeline view with auto-scroll
  - Toast notifications for user feedback
  - Menu bar extra for quick access

---

## Format Guidelines

### Categories
- **Added** for new features
- **Changed** for changes in existing functionality
- **Deprecated** for soon-to-be removed features
- **Removed** for now removed features
- **Fixed** for any bug fixes
- **Security** in case of vulnerabilities

### Release Format
- Use date-based releases: `YYYY-MM-DD - Brief Description`
- Example: `2025-10-10 - Timeline Improvements`
- Most recent releases at the top

### Writing Style
- Start with a verb (Added, Fixed, Changed, etc.)
- Be concise but descriptive
- Group related changes together under themed releases
- Include technical details but keep user-focused
