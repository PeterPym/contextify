# Contextify - Claude Code Terminal Integration

Contextify is a macOS HUD that bridges Claude Code CLI sessions in iTerm2 with a compose interface for reviewing and editing AI interactions. Built with Swift 6 + SwiftUI on Xcode 16 (macOS 26 SDK).

## Core Workflow
1. Work with Claude Code in iTerm2
2. Press **Cmd+Shift+K+K** to capture terminal content
3. Review/edit in Contextify compose panel
4. Send back to iTerm2 (or undo with **Cmd+Z** in iTerm2)

## Key Features

### Terminal Integration
- **Global hotkey capture**: Cmd+Shift+K+K grabs terminal content system-wide
- **iTerm2 integration**: Python daemon + AppleScript fallback for terminal reading
- **Compose interface**: Edit and refine captured text before sending to terminal
- **Undo support**: Cmd+Z in iTerm2 restores previous text sent by Contextify

### Automation
- **URL scheme**: `contextify://compose?text=...` for external integration
- **Launch agent**: Auto-starts iTerm2 daemon on system boot
- **Shell bindings**: Install with `bash scripts/install-shell-bindings.sh`

### Project Awareness
- **Git integration**: Displays current branch when project root is set
- **Persistent project root**: Tracks via security-scoped bookmarks (sandboxed mode)
- **Set Project Root** (File menu): Choose root directory to enable git branch display

## Quickstart

### Requirements
- Xcode 16+ (beta OK)
- macOS 15+ runtime
- iTerm2 (for terminal integration)

### Build & Run
```bash
# Build (auto-detects Xcode-beta if installed)
make build
# or
bash scripts/xc.sh build

# Run in Xcode
open Contextify/Contextify.xcodeproj
# Select scheme: Contextify
# Run on: My Mac
```

### Xcode Setup (First Time)

**1. Code Signing**

The project uses the personal Apple Developer certificate:
- **Team**: `VQ7RPM8H77` (Robert Banagale - rob@banagale.com)
- **Certificate**: Apple Development: rob@banagale.com (A4A8X8LW33)

This should be automatically selected in Xcode. If you need to change it:
1. Open `Contextify.xcodeproj` in Xcode
2. Select the Contextify target → Signing & Capabilities
3. Choose your preferred Team

**2. Command Line Tools**
```
Xcode → Settings → Locations → Command Line Tools
```
Set to **Xcode 16** (or Xcode-beta if installed)

**3. Console Filters (Recommended)**
Reduce log noise:
1. Open console (⇧⌘C)
2. Click **"Add Filter"**
3. Add: **TYPE Info**
4. Set **Comparison Options** to **"Match Any"**

This hides debug logs while showing Info/Notice/Error/Fault.

**4. Scheme Selection**
- Scheme: **Contextify**
- Target: **My Mac** (macOS 15.6+)

### Setup Terminal Integration
```bash
# Install shell bindings (adds Contextify commands to your shell)
bash scripts/install-shell-bindings.sh

# Grant accessibility permissions when prompted
# System Settings > Privacy & Security > Accessibility
# Enable: Contextify
```

## Enable Build Guard (Pre-commit)
```bash
# One-time setup
make hooks-setup
# or
make setup  # Also runs initial build

# What it does:
# - Runs headless build when Contextify/ files are staged
# - Blocks commit on build failure
# - Saves logs to build/logs/
# - Saves .xcresult to build/ResultBundles/
```

## Daily Commands
- **Build**: `make build` (or `bash scripts/xc.sh build`)
- **Test**: `make test`
- **Clean**: `make clean` (removes DerivedData)
- **Full setup**: `make setup` (hooks + build)

## Debugging & Log Capture
```bash
# Capture recent logs (last 5 minutes)
make logs  # → /tmp/contextify-recent.log

# Stream live logs
make logs-live  # → /tmp/contextify-live.log

# Build and auto-capture logs for 30 seconds
make debug  # → build/logs/runtime/contextify-YYYYMMDD-HHMMSS.log

# Clean database for fresh testing
make clean-db
```

**For Claude Code integration:** Captured logs can be shared directly:
```bash
make logs
# Then in chat: "have a look at /tmp/contextify-recent.log"
```

**Detailed guide:** See `scripts/QUICK-REFERENCE.md` and `scripts/LOG-CAPTURE-README.md`

## Cross-CLI Transcript Conversion

Contextify includes a bidirectional transcript converter that lets you **resume conversations across different AI coding assistants**. Convert transcripts between Claude Code and Codex CLI formats to continue where you left off.

### Quick Start

```bash
# Make executable (if not already)
chmod +x scripts/convert_transcript.py

# Convert Claude Code session to Codex CLI
./scripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  ~/.claude/projects/-Users-you-code-project/session-uuid.jsonl \
  ~/.codex/sessions/2025/10/24/rollout-2025-10-24T14-00-00-<uuid>.jsonl

# The converter shows you exactly how to resume:
# → cd ~/code/project && codex resume <uuid>

# Convert Codex CLI session to Claude Code
./scripts/convert_transcript.py \
  --from codex \
  --to claude-code \
  ~/.codex/sessions/2025/10/24/rollout-*.jsonl \
  ~/.claude/projects/-Users-you-code-project/imported-session.jsonl

# → cd ~/code/project && claude-code /resume imported-session
```

### What Gets Converted

**Preserves:**
- ✅ All user and assistant messages
- ✅ Timestamps and chronological order
- ✅ Session context (git branch, working directory)
- ✅ Content fidelity (text messages)

**Phase 1 Limitations:**
- ⚠️ Tool calls skipped (future: Phase 2)
- ⚠️ Threading simplified
- ⚠️ File snapshots dropped

### Features

- **Auto-generates proper filenames** for target CLI
- **Extracts session metadata** (project directory, git branch)
- **Shows resume instructions** with exact commands
- **Round-trip compatible** (Claude → Codex → Claude preserves messages)

### Testing Results

Real-world test with 723-line Claude Code transcript:
- **Claude Code → Codex:** 95 messages converted, 628 skipped (tool calls/metadata), 0 errors
- **Codex → Claude Code (round-trip):** 95 messages preserved, 0 errors

### Documentation

- **Usage guide:** `scripts/TRANSCRIPT_CONVERTER_README.md`
- **Format comparison:** `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
- **Parsers:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`

**Roadmap:**
- Phase 2: UI integration (one-click export from app)
- Phase 3: Tool call preservation
- Phase 4: Support for more AI assistants (Cursor, Aider)

## Architecture Notes

### Data Layer
- **Database**: SQLite backend via GRDB.swift
- **Location**: `~/Library/Application Support/Contextify/transcripts.db`
- **Features**:
  - Streaming transcript ingestion with `HooverEngine`
  - Real-time file monitoring via `TranscriptWatcher`
  - LLM-powered timeline summaries (Apple Intelligence/FoundationLLM)
  - Crash-safe checkpointing and WAL mode
- **Components**:
  - `TranscriptOrchestrator`: Coordinates all database operations
  - `DatabaseManager`: Singleton connection pool
  - `Repositories`: Type-safe GRDB repositories (Projects, Transcripts, Entries)
- **Documentation**:
  - Usage guide: `app/Sources/ContextifyCore/Database/README.md`
  - Architecture: `build/notes/technical-reference/sql-backend-architecture.md`

### Timeline & Conversation Monitoring
- **ConversationMonitor**: Main UI-facing component for timeline display
- **TimelineCacheMissGenerator**: LLM-powered summary generation for cache misses
- **TimelineState**: Observable state container for SwiftUI integration
- **SQL-backed caching**: Timeline summaries cached by content+window hash
- **Provider support**: Claude Code and Codex CLI formats
- **Apple Intelligence requirement:** Timeline summaries require macOS 26.0+. On older macOS versions, basic (non-LLM) summaries are shown.
- **Documentation**:
  - Cache + LLM: `build/notes/technical-reference/timeline-cache-llm-architecture.md`
  - State management: `build/notes/technical-reference/conversation-monitor-state-architecture.md`

### Terminal Content Capture
- **Primary method**: iTerm2 Python API via daemon (`ITerm2DaemonClient.swift`)
- **Fallback**: AppleScript when Python API unavailable
- **Parser**: Extracts Claude Code input from terminal buffer (`ClaudeCodeParser`)
- **Security**: Requires Accessibility permissions for keyboard monitoring

### Compose Workflow
- **URL scheme handler**: Routes `contextify://` URLs to compose interface
- **Text editor**: SwiftUI `TextEditor` with focus management (`FocusableTextView.swift`)
- **Undo manager**: `TerminalUndoManager.swift` - tracks text history for Cmd+Z

### Project Root Resolution
**Startup precedence:**
1. `CONTEXTIFY_PROJECT_ROOT` environment variable
2. Security-scoped bookmark (sandboxed mode)
3. Persisted path from UserDefaults
4. Falls back to no project

**Git monitoring:**
- Watches `.git/HEAD`, ref files, and `packed-refs` for branch changes
- Sandboxed: parses HEAD directly
- Non-sandboxed: runs `git rev-parse --abbrev-ref HEAD` with 2s timeout
- Handles worktrees (`.git` file with `gitdir:` pointer)

### Concurrency
- **Swift 6 strict concurrency** throughout
- `@MainActor` for UI components and ViewModels
- `async/await` for I/O operations
- `Sendable` protocols for cross-actor data
- Database operations isolated via GRDB's thread-safe queue

## Key Files

### Database Layer (ContextifyCore)
- `DatabaseManager.swift` - Singleton GRDB connection pool
- `DatabaseSchema.swift` - SQL schema and migrations
- `TranscriptOrchestrator.swift` - High-level database coordinator
- `Repositories.swift` - Type-safe GRDB repositories
- `HooverEngine.swift` - Streaming transcript ingestion
- `TranscriptWatcher.swift` - File system monitoring
- `Models.swift` - Database models (Project, Transcript, Entry, etc.)
- See `app/Sources/ContextifyCore/Database/README.md` for details

### Timeline & Monitoring
- `ConversationMonitor.swift` - Main timeline component (observable state)
- `TimelineCacheMissGenerator.swift` - LLM-powered summary generation
- `TimelineModels.swift` - Timeline data models
- `FoundationLLM.swift` - Apple Intelligence integration
- `TranscriptInventoryView.swift` - Session browser UI

### Terminal Integration
- `GlobalHotkeyManager.swift` - Cmd+Shift+K+K hotkey implementation
- `TerminalContentReader.swift` - Terminal capture logic
- `ITerm2DaemonClient.swift` - Python daemon integration
- `ITerm2Bridge.swift` - iTerm2 automation bridge
- `ClaudeCodeParser.swift` - Extracts input from terminal buffer

### Compose Workflow
- `ComposeURLRouter.swift` - URL scheme handling
- `ComposeWindowManager.swift` - Compose window lifecycle
- `FocusableTextView.swift` - Enhanced text editor
- `TerminalUndoManager.swift` - Undo functionality

### Project Context (ContextifyCore)
- `HUDViewModel.swift` - Main view model (project root, git monitoring)
- `GitRepositoryResolver.swift` - Git detection and branch tracking
- `HUDPreferences.swift` - UserDefaults management

### UI
- `ContentView.swift` - Main window UI
- `ConversationTimelineView.swift` - Timeline display
- `TimelineEntryRow.swift` - Timeline entry UI

### Metadata & Lifecycle
- `TranscriptMetadataOrchestrator.swift` - Metadata generation coordinator
- `SidecarMetadataStore.swift` - JSON sidecar metadata persistence
- `LaunchAgentManager.swift` - Daemon lifecycle management
- `WindowTitleWriter.swift` - Window title updates

## Documentation

### Technical Architecture References
- **SQL Backend:** `build/notes/technical-reference/sql-backend-architecture.md`
- **Timeline Cache + LLM:** `build/notes/technical-reference/timeline-cache-llm-architecture.md`
- **State Management:** `build/notes/technical-reference/conversation-monitor-state-architecture.md`
- **Database Usage Guide:** `app/Sources/ContextifyCore/Database/README.md`

### Project Documentation
- **Apple docs**: `docs/knowledge/apple/readme.md`
- **Contributing**: `AGENTS.md`
- **Project guidance**: `CLAUDE.md`

### SwiftUI Integration Tip
```swift
// ContentView.swift: ConversationMonitor injected via environment
@Environment(ConversationMonitor.self) private var monitor
```

## Troubleshooting

### Capturing logs for debugging
**Quick capture:**
```bash
make logs  # Captures last 5 minutes
```

**Then share with Claude Code:**
```
have a look at /tmp/contextify-recent.log
```

This allows Claude Code to read logs directly and diagnose issues faster. See `scripts/QUICK-REFERENCE.md` for detailed workflows.

### Global hotkey not working
1. Check accessibility permissions: System Settings > Privacy & Security > Accessibility
2. Ensure Contextify is enabled
3. Restart Contextify
4. **Debug**: Capture logs with `make logs` and check for hotkey registration errors

### Terminal capture failing
1. Verify iTerm2 is running
2. Check daemon status: `ps aux | grep iterm2_daemon.py`
3. Restart daemon via Launch Agent or `launchctl`
4. Fallback to AppleScript (automatic if daemon unavailable)
5. **Debug**: Run `make logs-live` while reproducing the issue

### URL scheme not working
1. Reinstall shell bindings: `bash scripts/install-shell-bindings.sh`
2. Verify URL handler registration: `defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers`
3. Restart Contextify
4. **Debug**: Check logs with `make logs` for URL handling errors

### Database issues
If you see FK constraint errors or corrupt data:
```bash
make clean-db  # Clears database for fresh start
make debug     # Rebuilds and captures logs
```
