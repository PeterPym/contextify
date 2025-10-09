# Completed Work

## 2025-10-02 - Compose Panel URL Handler & Shell Integration

**Branch:** `feature/magic-input`

**Completed:**
- ✅ Restructured Xcode project and build configuration
- ✅ Extracted HUDCore module with Swift Package Manager
- ✅ Added compose workflow and automation support (panel, URL routing, window management)
- ✅ Implemented iTerm2 integration bridge
- ✅ Added window management utilities
- ✅ Updated main app structure and views
- ✅ Enhanced test suites with helpers
- ✅ Fixed shell keybinding issues:
  - Fixed zsh substring syntax
  - Removed trailing newline in base64 encoding
  - Fixed Python quote escaping in URL encoding

**How it works:**
- URL scheme handler: `contextify-dev://compose?text64=...`
- Shell keybinding: Ctrl-X Ctrl-K sends current buffer/selection to compose panel
- Panel reuses single NSPanel instance (not destroyed on close)
- Text delivered to iTerm2 via AppleScript

**Files:** See `build/notes/archive/2025-10-02-compose-panel.md` for technical briefing

---

## 2025-10-02 - Inline Compose Simplification

**Branch:** `feature/inline-compose`

**Completed:**
- ✅ Transformed main window into focused compose interface
- ✅ Removed modal compose panel in favor of inline textarea
- ✅ Simplified UI: Header (project/branch) + Compose section
- ✅ Removed URL ingestion, drop zone, session/checkpoint features
- ✅ Added iTerm2 target session display with refresh button
- ✅ Updated URL routing to populate main window instead of modal
- ✅ Changed shell keybinding from Ctrl-X Ctrl-K to Ctrl-K Ctrl-K
- ✅ Added getCurrentSessionName() to ITerm2Bridge
- ✅ Documented removed features for future restoration
- ✅ Created future-compose-features.md with enhancement ideas

**Final UI:**
```
┌────────────────────────────────────────────┐
│ 📁 ProjectName  🌿 branch                 │
├────────────────────────────────────────────┤
│ Send to: ✳ Tab Name (claude) ⟳           │
│ ┌────────────────────────────────────────┐ │
│ │ Compose textarea (monospaced)          │ │
│ │                                        │ │
│ └────────────────────────────────────────┘ │
│                          [Send ⌘↩]         │
└────────────────────────────────────────────┘
```

**Behavior:**
- Ctrl-K Ctrl-K in terminal → text appears in compose area (replaces existing)
- Edit text, Cmd+Return to send to iTerm2
- Text clears on successful send
- Toast notifications for success/error

**Removed (documented for future):**
- File/URL ingestion workflow
- Session management (Session-001, checkpoints)
- Output directory management
- Drop zone for files

**Files:**
- Deleted: ComposeWindowController, ComposeSheet, ComposePresenter
- Modified: ContentView (simplified), ComposeURLRouter (routes to main window)
- Added: future-compose-features.md, comments documenting removed UI

---

## 2025-10-03 - Global Hotkey & Claude Code Parser

**Branch:** `feature/inline-compose` (continued)

**Completed:**
- ✅ Implemented global hotkey (Cmd+Shift+K+K) to capture Claude Code terminal input
- ✅ Added iTerm2 Python API integration with virtual environment setup
- ✅ Fixed Claude Code parser to extract active input using index-based slicing
- ✅ Discovered and handled Unicode issue: Claude Code uses U+00A0 (non-breaking space) after `>`
- ✅ Added selection API fallback in Python reader to capture uncommitted input buffer
- ✅ Enhanced status line detection with variant matching
- ✅ Added comprehensive debug logging for parser troubleshooting

**How it works:**
- Cmd+Shift+K+K hotkey → iTerm2 Python API reads terminal content
- Python script tries selection API first (captures active input), falls back to screen contents
- ClaudeCodeParser extracts input by finding status line (⏵⏵), scanning backwards for separator lines
- Input extraction: skip first 2 chars (> and non-breaking space), take rest of line
- Extracted text populates compose textarea in Contextify

**Technical Details:**
- Root cause: Claude Code uses U+00A0 (non-breaking space) not U+0020 after prompt `>`
- Solution: Bypass character matching entirely with `currentLine.index(startIndex, offsetBy: 2)`
- Python bundled in app with virtual environment (iterm2 module)
- iTerm2 API socket connection via `/Users/rob/Library/Application Support/iTerm2/private/socket`

**Files:**
- Added: `scripts/iterm2_reader.py` (Python API terminal reader with selection fallback)
- Added: `Contextify/Contextify/ClaudeCodeParser.swift` (index-based input extraction)
- Modified: `Contextify/Contextify/TerminalContentReader.swift` (Python/AppleScript coordination)
- Modified: Xcode project settings (Python bundling, sandbox disabled for debugging)

**Known Issues:**
- Python script has noticeable execution delay (needs performance optimization)

---

