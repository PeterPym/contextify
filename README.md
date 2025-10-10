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

**1. Command Line Tools**
```
Xcode → Settings → Locations → Command Line Tools
```
Set to **Xcode 16** (or Xcode-beta if installed)

**2. Console Filters (Recommended)**
Reduce log noise:
1. Open console (⇧⌘C)
2. Click **"Add Filter"**
3. Add: **TYPE Info**
4. Set **Comparison Options** to **"Match Any"**

This hides debug logs while showing Info/Notice/Error/Fault.

**3. Scheme Selection**
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

## Architecture Notes

### Terminal Content Capture
- **Primary method**: iTerm2 Python API via daemon (`ITerm2DaemonClient.swift`)
- **Fallback**: AppleScript when Python API unavailable
- **Parser**: Extracts Claude Code input from terminal buffer (`ClaudeCodeParser`)
- **Security**: Requires Accessibility permissions for keyboard monitoring

### Compose Workflow
- **URL scheme handler**: `ComposePresenter.swift` - routes `contextify://` URLs
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

## Key Files

### Core Components
- `GlobalHotkeyManager.swift` - Cmd+Shift+K+K hotkey implementation
- `TerminalContentReader.swift` - Terminal capture logic
- `ITerm2DaemonClient.swift` - Python daemon integration
- `ITerm2Bridge.swift` - iTerm2 automation bridge
- `ComposePresenter.swift` - URL scheme handling
- `HUDViewModel.swift` - Main view model (in `ContextifyCore`)

### UI
- `ContentView.swift` - Main window UI
- `ComposeSheet.swift` - Compose workflow UI
- `FocusableTextView.swift` - Enhanced text editor

### Integration
- `LaunchAgentManager.swift` - Daemon lifecycle management
- `TerminalUndoManager.swift` - Undo functionality
- `WindowTitleWriter.swift` - Window title updates

## Documentation
- **Apple docs**: `docs/knowledge/apple/readme.md`
- **Contributing**: `AGENTS.md`
- **Project guidance**: `CLAUDE.md`

## Troubleshooting

### Global hotkey not working
1. Check accessibility permissions: System Settings > Privacy & Security > Accessibility
2. Ensure Contextify is enabled
3. Restart Contextify

### Terminal capture failing
1. Verify iTerm2 is running
2. Check daemon status: `ps aux | grep iterm2_daemon.py`
3. Restart daemon via Launch Agent or `launchctl`
4. Fallback to AppleScript (automatic if daemon unavailable)

### URL scheme not working
1. Reinstall shell bindings: `bash scripts/install-shell-bindings.sh`
2. Verify URL handler registration: `defaults read com.apple.LaunchServices/com.apple.launchservices.secure LSHandlers`
3. Restart Contextify
