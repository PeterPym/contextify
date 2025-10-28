# Project Switcher - Manual QA Checklist

**Feature:** Multi-project navigation with horizontal tabs, unread badges, and keyboard shortcuts
**Target:** Phase 0-5 implementation (85% complete)
**Time Estimate:** 20-30 minutes

---

## Pre-Test Setup

- [ ] **Clean database:** `make clean-db` (creates backup first)
- [ ] **3+ projects required:** Ensure you have at least 3 projects with active Claude Code sessions
- [ ] **Known project paths:**
  - Project A: `/Users/rob/code/projects/contextify`
  - Project B: (your second project path)
  - Project C: (your third project path)

---

## Test Group 1: Basic Discovery & Display (5 min)

### TC1.1: Auto-Discovery on Launch
- [ ] Kill Contextify if running
- [ ] Launch: `bash scripts/xc.sh build`
- [ ] **Expected:** Status bar shows "Discovering projects..." briefly
- [ ] **Expected:** Horizontal tab bar appears with 3+ project tabs
- [ ] **Expected:** Current project tab is highlighted (blue background)

### TC1.2: Tab Content
For each visible tab:
- [ ] Shows project name (e.g., "contextify")
- [ ] Shows unread count badge if >0 (e.g., "(3)" in blue)
- [ ] No count shown if unread = 0
- [ ] Tab width adjusts to content (not fixed width)

---

## Test Group 2: Navigation & Switching (5 min)

### TC2.1: Click Navigation
- [ ] Click on a non-active project tab
- [ ] **Expected:** Tab switches to active state (blue background)
- [ ] **Expected:** Timeline refreshes to show that project's entries
- [ ] **Expected:** Unread badge clears for newly active project
- [ ] **Expected:** Status bar shows project path update

### TC2.2: Keyboard Navigation (Forward)
- [ ] Press `Cmd+Shift+]`
- [ ] **Expected:** Moves to next project tab (wraps to first if at end)
- [ ] **Expected:** Timeline refreshes
- [ ] **Expected:** Smooth spring animation (0.6s response, 0.85 damping)

### TC2.3: Keyboard Navigation (Backward)
- [ ] Press `Cmd+Shift+[`
- [ ] **Expected:** Moves to previous project tab (wraps to last if at start)
- [ ] **Expected:** Timeline refreshes

### TC2.4: Auto-Scroll to Active Tab
- [ ] Have 5+ projects visible (requires horizontal scrolling)
- [ ] Use `Cmd+Shift+]` to cycle to an off-screen project
- [ ] **Expected:** ScrollView auto-scrolls to center the active tab
- [ ] **Expected:** Animation is smooth and not jarky

---

## Test Group 3: Unread Badge Behavior (5 min)

### TC3.1: Badge Display
- [ ] Note current active project
- [ ] Switch to different project (Project B)
- [ ] In terminal, make a change to Project A (e.g., create a file, run a command in Claude Code)
- [ ] Wait 10 seconds for transcript update
- [ ] **Expected:** Project A tab shows unread badge (e.g., "(1)")

### TC3.2: Badge Clearing
- [ ] Click on Project A tab (the one with unread badge)
- [ ] **Expected:** Badge disappears immediately upon switching
- [ ] **Expected:** Timeline shows the new entries

### TC3.3: Badge Capping
- [ ] If you have a project with 100+ unread entries, check display
- [ ] **Expected:** Badge shows "(99+)" not the full count

---

## Test Group 4: LLM Request Cancellation (5 min)

### TC4.1: Rapid Switching Stress Test
- [ ] Ensure you have 2+ projects with many entries (50+ each)
- [ ] Rapidly press `Cmd+Shift+]` 10 times in quick succession
- [ ] **Expected:** Tabs switch quickly without lag
- [ ] Wait 10 seconds, check status bar
- [ ] **Expected:** Status bar shows cleared pending misses log:
  ```
  Cleared X pending misses for inactive projects (kept Y for active project)
  ```

### TC4.2: No Indefinite Hanging
- [ ] After rapid switching, monitor for 30 seconds
- [ ] **Expected:** No ongoing "Sending delete session" or retry loops
- [ ] **Expected:** LLM queue settles within 30s
- [ ] **Expected:** Status bar errors count returns to 0

---

## Test Group 5: Edge Cases (5 min)

### TC5.1: Single Project
- [ ] Test with only 1 project in database
- [ ] **Expected:** Tab bar shows single tab
- [ ] **Expected:** Keyboard shortcuts do nothing (or wrap to same project)
- [ ] **Expected:** No crashes

### TC5.2: Zero Projects
- [ ] `make clean-db` and launch fresh
- [ ] **Expected:** Tab bar empty or shows "No projects"
- [ ] **Expected:** Timeline empty
- [ ] **Expected:** No crashes

### TC5.3: Long Project Names
- [ ] Test with project path like `/Users/rob/this-is-a-very-long-project-name-for-testing`
- [ ] **Expected:** Tab truncates or wraps gracefully
- [ ] **Expected:** Still readable and clickable

### TC5.4: Project Name Collisions
- [ ] Test with two projects named "test" in different directories
- [ ] **Expected:** Tabs show distinguishing info (path or unique ID)
- [ ] **Expected:** Can switch between them correctly

---

## Test Group 6: Integration (5 min)

### TC6.1: Projects Window Sync
- [ ] Open Projects window (`Cmd+Shift+P`)
- [ ] Click on a project in the list
- [ ] **Expected:** Tab bar updates to show that project as active
- [ ] **Expected:** Timeline refreshes

### TC6.2: Manual Project Root Change
- [ ] File → Open project... → Select new folder
- [ ] **Expected:** New project appears in tab bar
- [ ] **Expected:** Becomes active tab
- [ ] **Expected:** Timeline refreshes

### TC6.3: Status Bar Monitoring
- [ ] Open status bar (visible by default)
- [ ] Switch between projects with pending LLM work
- [ ] **Expected:** Status bar shows:
  - Timeline queue updates (pending count changes)
  - Cleared misses when switching
  - No error accumulation over time

---

## Test Group 7: Performance (Optional, 5 min)

### TC7.1: Large Project Count (10+ projects)
- [ ] Test with 10+ projects discovered
- [ ] **Expected:** Tab bar horizontally scrollable
- [ ] **Expected:** No lag when switching
- [ ] **Expected:** Auto-scroll works correctly

### TC7.2: Memory Stability
- [ ] Run Activity Monitor
- [ ] Switch between projects 20 times
- [ ] **Expected:** Memory usage stable (no leaks)
- [ ] **Expected:** CPU settles to idle after switching stops

---

## Known Limitations (Document, Don't Test)

1. **Phase 4 (Performance)** - Not validated:
   - No formal stress test with 20+ projects
   - No CPU/memory profiling telemetry
   - No idle resource usage baseline

2. **Phase 6 (QA/Polish)** - Not complete:
   - Accessibility audit (VoiceOver, keyboard-only) not done
   - Documentation not updated in CLAUDE.md

3. **Animation Tuning:**
   - Spring animation may need further adjustment based on feel
   - Currently: 0.6s response, 0.85 damping (slower than original)

---

## Pass/Fail Criteria

**Pass:** All Test Groups 1-6 complete with ✅
**Partial Pass:** Test Groups 1-5 pass, Group 6 has 1-2 issues
**Fail:** Any crash, data loss, or >3 failed test cases

---

## Bug Reporting Template

If you find issues, report with:
```
**Test Case:** TC2.3 - Keyboard Navigation (Backward)
**Steps:** Press Cmd+Shift+[
**Expected:** Moves to previous project
**Actual:** Moves to next project instead
**Severity:** High
**Logs:** (attach /tmp/contextify-recent.log)
```

---

## Notes

- Test with **real projects**, not synthetic test data
- If LLM timeouts occur, check logs: `make logs`
- Database backup location: `build/db-backups/`
- Restore if needed: `make db-restore`
