# Contextify App (Xcode Project)

This folder contains the macOS SwiftUI app for Contextify - a HUD that monitors Claude Code and Codex CLI transcripts with real-time LLM-powered summaries.

## Run
- Open `Contextify.xcodeproj` and select the `Contextify` scheme.
- Run on "My Mac". Minimum macOS: 15. Base SDK: macOS 26 (Xcode 16 beta).

## Build (CLI)
- Preferred: `bash ../scripts/xc.sh build` (auto-detects Xcode-beta; logs to `../build/logs/`).
- Result bundles saved to `../build/ResultBundles/` for Xcode inspection.

## Core Features

### Transcript Monitoring
- Automatically discovers transcripts in `~/.claude/projects/` and `~/.codex/sessions/`
- Real-time file watching with automatic ingestion
- SQLite backend (v33) with crash-safe checkpointing
- See `ConversationMonitor.swift` for timeline implementation

### Timeline View
- LLM-generated summaries for each conversation turn
- Disposition classification (directive, completion, question, etc.)
- Cached summaries with content+window hash-based invalidation
- Provider-specific branding (Claude Code: orange, Codex CLI: blue)

### Project Management
- Multi-project discovery with git integration
- Unread message tracking
- Project switcher UI
- Git branch display and monitoring

## Additional Features

### File Ingestion
- Drag/drop files or submit a URL → timestamped Markdown with basic metadata
- Dropped files copied to `~/Contextify/outputs/ingest/`
- "Checkpoint" writes a Markdown file under `~/Contextify/outputs/checkpoints/`
- Artifacts in `~/Contextify/outputs/` (ignored by git)

### Terminal Integration
- "Compose → iTerm2" button opens monospaced editor with newline toggle
- On first send, macOS prompts to allow Contextify to control iTerm2; choose **Allow**
- Delivery failures fall back to copying payload to clipboard
- Shell bindings: `bash scripts/build/install-shell-bindings.sh`


## Architecture

**Key Components:**
- `ConversationMonitor.swift` - Main timeline component (observable state)
- `TranscriptOrchestrator.swift` - High-level database coordinator
- `TimelineCacheMissGenerator.swift` - LLM-powered summary generation
- `HUDViewModel.swift` - Main app coordinator (project root, git monitoring)
- `DatabaseManager.swift` - Singleton GRDB connection pool

**Documentation:**
- Technical architecture: `../build/docs/architecture/`
- Database usage: `../app/Sources/ContextifyCore/Database/README.md`
- Development guide: `../build/docs/guides/DEVELOPMENT.md`

## Pre‑commit Guard
- Enable hooks at repo root: `git config core.hooksPath .githooks`
- Commits touching `Contextify/` will build the app; failures block the commit with logs

## Technical Notes
- Swift 6 + SwiftUI with strict concurrency checking
- `@MainActor` for UI components and ViewModels
- Database operations isolated via GRDB's thread-safe queue
- Security-scoped bookmarks for sandboxed file access (App Store builds)
