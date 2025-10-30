# QA Test Plan: Production Fixes Branch

## Overview
Test plan for `feature/production-fixes` branch covering project management, UI improvements, and stability fixes.

## 1. Project Tab Management

### Drag-and-Drop Reordering
- [ ] Drag project tab to new position - indicator shows insertion point
- [ ] Drop tab - single DB write, no flicker
- [ ] Drag over gaps between tabs - no insertion indicator (non-responsive)
- [ ] Order persists across app restarts
- [ ] Active project auto-switches to dropped tab

### Keyboard Navigation
- [ ] `Cmd+Shift+]` cycles forward through projects
- [ ] `Cmd+Shift+[` cycles backward through projects
- [ ] Shortcuts work with 1, 2, and 10+ projects
- [ ] Active tab scrolls into view automatically

### Context Menu
- [ ] Right-click tab shows "Hide from Tabs"
- [ ] "Restore All Hidden Tabs" only appears when projects are hidden
- [ ] Hidden projects removed from tab bar immediately
- [ ] Orphaned projects show warning badge (directory missing)

## 2. Projects Window

### Current Project Tracking
- [ ] Opens with correct project marked "CURRENT" on first launch
- [ ] "CURRENT" badge updates when switching tabs in main window
- [ ] "Set as Current" updates main window tabs immediately
- [ ] Refresh button re-detects current project correctly

### Provider Badges
- [ ] Claude Code shows orange logomark (not blue emoji)
- [ ] Codex shows white logomark (not yellow emoji)
- [ ] Matches main window and timeline styling

## 3. Transcript Inventory

### Session Selection
- [ ] Click session from different project switches active tab in main window
- [ ] Timeline loads selected session correctly
- [ ] Works across projects (not just current)

### Deletion
- [ ] Delete transcript removes from DB and UI
- [ ] "Cleanup Missing" removes transcripts for deleted files
- [ ] Bulk cleanup shows progress, handles 100+ files

## 4. Status Bar

### LLM Processing
- [ ] Never shows "Processing 0 items"
- [ ] ETA hidden when queue empty
- [ ] Shows progress for timeline summaries
- [ ] Shows progress for transcript metadata generation

## 5. Non-Git Projects

### Project Root Detection
- [ ] Projects without `.git` dir can be set as current
- [ ] Branch shows "—" for non-Git projects
- [ ] Timeline and ingestion work normally

## 6. Stability & Performance

### Concurrency
- [ ] No crashes during rapid project switching
- [ ] iTerm2 session detection works without hangs
- [ ] Projects window updates don't block main thread

### Database
- [ ] Bulk reorder succeeds under concurrent reads
- [ ] No SQLITE_BUSY errors during normal use
- [ ] Migrations v18-v20 apply cleanly on upgrade

### Logging
- [ ] Console logs minimal at INFO level during idle
- [ ] No emoji/verbose logs in production
- [ ] Debug filter shows detailed flow when needed

## 7. Edge Cases

### Orphaned Projects
- [ ] Project with missing directory shows badge
- [ ] Can still view transcripts in DB
- [ ] Delete or restore handles gracefully

### Multi-Window
- [ ] Main + Projects windows stay in sync
- [ ] Main + Inventory windows stay in sync
- [ ] No duplicate observers or memory leaks

### Startup
- [ ] First launch detects projects correctly
- [ ] Relaunch remembers last active project
- [ ] Hidden projects remain hidden across restarts

## Pass Criteria
- All checkboxes pass
- No console errors or warnings
- No crashes during 10-minute stress test (rapid switching, window open/close)
- Memory stable (Activity Monitor: no leaks over 30 minutes)
