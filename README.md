# Contextify

A macOS HUD for AI-assisted development sessions. Contextify monitors Claude Code and Codex CLI conversations, providing real-time timeline views with LLM-powered summaries, terminal integration, and project-aware context management.

**Built with:** Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK)

## What It Does

Contextify is a development companion that:

1. **Monitors AI coding sessions** - Watches `~/.claude/projects/` and `~/.codex/sessions/` for live conversation updates
2. **Generates timeline summaries** - Uses Apple Intelligence (FoundationLLM) to create contextual summaries of conversation windows
3. **Integrates with terminals** - Capture and compose text from iTerm2 with global hotkeys
4. **Tracks project context** - Git branch awareness, project switching, and persistent session history

**Core workflow:**
- Work with Claude Code or Codex CLI in your terminal
- Contextify automatically detects new transcript entries
- View conversation timeline with LLM-generated summaries
- Press **Cmd+Shift+K+K** to capture terminal content for editing/refinement

## Key Features

### Conversation Timeline
- **Real-time monitoring**: File system watcher on transcript directories
- **LLM summaries**: Apple Intelligence-powered timeline summarization (macOS 26.0+)
- **Project switching**: Browse and switch between multiple AI sessions
- **Session inventory**: Complete browsable history of conversations and metadata

### Terminal Integration
- **Global hotkey capture**: Cmd+Shift+K+K grabs terminal content system-wide
- **iTerm2 integration**: Python daemon + AppleScript fallback
- **Compose interface**: Edit and refine captured text before sending to terminal
- **Undo support**: Cmd+Z in iTerm2 restores previous text

### Project Awareness
- **Git integration**: Displays current branch and repository status
- **Multi-project support**: Tracks multiple AI sessions across different repositories
- **Security-scoped access**: Sandbox-friendly bookmark system for App Store builds

## Getting Started

### Requirements
- Xcode 16+ (beta OK)
- macOS 15+ runtime
- iTerm2 (for terminal integration)

### Quick Build
```bash
# Build (auto-detects Xcode-beta if installed)
make build

# Run in Xcode
open Contextify/Contextify.xcodeproj
# Select scheme: Contextify, Run on: My Mac
```

### First-Time Setup

1. **Command Line Tools**: Xcode → Settings → Locations → Set to Xcode 16
2. **Terminal Integration**: `bash scripts/install-shell-bindings.sh`
3. **Accessibility Permissions**: System Settings > Privacy & Security > Accessibility > Enable Contextify
4. **Pre-commit Hooks** (optional): `make hooks-setup` to enable build guards

**For detailed setup and troubleshooting:** See `build/docs/guides/DEVELOPMENT.md`

### Common Commands
```bash
make build      # Build the app
make test       # Run tests
make clean      # Clean DerivedData
make logs       # Capture recent logs to /tmp/contextify-recent.log
make clean-db   # Reset database (asks for approval)
```

## Cross-CLI Transcript Conversion

Resume AI coding conversations across different assistants. The transcript converter enables bidirectional conversion between Claude Code and Codex CLI session formats.

### Usage

```bash
# Convert Claude Code → Codex CLI
./scripts/convert_transcript.py \
  --from claude-code --to codex \
  ~/.claude/projects/<encoded-path>/session.jsonl \
  ~/.codex/sessions/2025/10/24/rollout-*.jsonl

# Convert Codex CLI → Claude Code
./scripts/convert_transcript.py \
  --from codex --to claude-code \
  ~/.codex/sessions/2025/10/24/rollout-*.jsonl \
  ~/.claude/projects/<encoded-path>/imported.jsonl
```

**What's preserved:** User/assistant messages, timestamps, session context (git branch, working directory)
**Current limitations:** Tool calls, threading, and file snapshots not yet converted (Phase 2+)

**Documentation:** `scripts/TRANSCRIPT_CONVERTER_README.md` | `build/docs/specifications/transcript-formats.md`

## Architecture Overview

Contextify uses a SQL backend (GRDB.swift) with real-time transcript monitoring and LLM-powered summaries.

### Key Components
- **Database**: SQLite (schema v26) at `~/Library/Application Support/Contextify/contextify.db`
  - `HooverEngine`: Streaming JSONL transcript ingestion (1000 lines/batch)
  - `TranscriptWatcher`: File system monitoring for live updates
  - `TranscriptOrchestrator`: High-level database coordinator
- **Timeline**: `ConversationMonitor` + `TimelineCacheMissGenerator` (LLM summaries via Apple Intelligence)
- **Terminal**: iTerm2 Python API daemon + AppleScript fallback for content capture
- **Project Context**: `HUDViewModel` handles git monitoring, project root resolution, security-scoped bookmarks

**Concurrency**: Swift 6 strict concurrency with `@MainActor` for UI, `async/await` for I/O, GRDB's thread-safe queue for database operations

### Documentation

**For contributors:** See `AGENTS.md` for repository guidelines, coding style, and development workflow

**Architecture deep-dives:**
- SQL Backend: `build/docs/architecture/sql-backend.md`
- Timeline & LLM: `build/docs/components/timeline-cache.md`
- State Management: `build/docs/architecture/conversation-monitor-state.md`
- Components Index: `build/docs/architecture/COMPONENTS.md`
- Database Usage: `app/Sources/ContextifyCore/Database/README.md`

**Operations:**
- Build Guide: `build/docs/guides/DEVELOPMENT.md`
- Debugging: `scripts/logging/README.md` (automated test harnesses)
- Database Management: `build/docs/operations/DATABASE-LOCATIONS.md`
- Release Process: `scripts/RELEASE.md`

## Troubleshooting

### Log Capture
```bash
make logs       # Capture last 5 minutes → /tmp/contextify-recent.log
make logs-live  # Stream live logs
make debug      # Build + 30s log capture
```

Share logs with Claude Code: `have a look at /tmp/contextify-recent.log`

**Detailed debugging:** `scripts/logging/README.md` (automated test harnesses)

### Common Issues

**Global hotkey (Cmd+Shift+K+K) not working:**
- Check: System Settings > Privacy & Security > Accessibility > Enable Contextify
- Restart Contextify and check logs: `make logs`

**Terminal capture failing:**
- Verify iTerm2 is running
- Check daemon: `ps aux | grep iterm2_daemon.py`
- Fallback to AppleScript is automatic

**Database errors:**
```bash
make clean-db  # Reset database (asks for approval)
make debug     # Rebuild + capture logs
```

**For complete troubleshooting:** See `build/docs/guides/DEVELOPMENT.md`
