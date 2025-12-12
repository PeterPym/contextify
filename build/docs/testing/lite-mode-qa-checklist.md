# Lite Mode QA Checklist

**Purpose:** Validate Contextify Lite Mode functionality on macOS 15 (Sequoia).
**When to Run:** Before merging `feature/legacy-macos-support` or any changes affecting lite mode detection.
**VM Setup:** See `macos-vm-setup.md`

---

## Pre-Test Setup

- [ ] macOS 15 VM running (see `macos-vm-setup.md`)
- [ ] Contextify DMG installed on VM
- [ ] Console.app open, filtered to `process:Contextify`
- [ ] At least one Claude Code or Codex transcript exists (or will create during test)

---

## Test Suite

### 1. App Launch (Critical)

**Goal:** Verify app launches without dyld crash.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 1.1 | Launch Contextify from Applications | App opens, no crash | | |
| 1.2 | Check Console for dyld errors | None present | | |
| 1.3 | Check Console for `[LLM-AVAILABILITY]` | Shows "Lite mode - macOS version < 26" | | |

**If 1.1 fails:** The `#if canImport(FoundationModels)` guards are not working. Do not proceed.

---

### 2. Status Bar Display

**Goal:** Verify status bar shows correct lite mode state.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 2.1 | Look at status bar (bottom of HUD) | Shows "Lite Mode" text | | |
| 2.2 | Verify NOT showing "AI Unavailable" | Correct - should say "Lite Mode" | | |
| 2.3 | Verify NOT showing "Apple Intelligence" | Correct - not available on macOS 15 | | |

---

### 3. Timeline Display

**Goal:** Verify timeline shows entries with appropriate fallback content.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 3.1 | View timeline with existing transcripts | Entries display without crash | | |
| 3.2 | Check user message format | Shows "User: [action label]" (e.g., "User: Instruction") | | |
| 3.3 | Check assistant message format | Shows "Assistant: [action label]" (e.g., "Assistant: Code change") | | |
| 3.4 | Check raw content preview | Shows first ~100 chars of actual message | | |
| 3.5 | Verify NO summary text | Summaries are disabled, not broken | | |

**Fallback content examples:**
- "User: Instruction" + raw preview
- "User: Question" + raw preview
- "Assistant: Code change" + raw preview
- "Assistant: Explanation" + raw preview

---

### 4. Core Functionality

**Goal:** Verify non-LLM features work normally.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 4.1 | Switch between projects (if multiple) | Project switch works | | |
| 4.2 | Scroll timeline up/down | Smooth scrolling, no crashes | | |
| 4.3 | Click on timeline entry | Expands/collapses correctly | | |
| 4.4 | Open Settings | Settings window opens | | |
| 4.5 | Open Transcripts window | Window opens, lists transcripts | | |
| 4.6 | Open Projects window | Window opens, lists projects | | |

---

### 5. Search (if implemented)

**Goal:** Verify search works in lite mode.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 5.1 | Open Quick Search (Cmd+K or Cmd+F) | Search UI appears | | |
| 5.2 | Search for known term | Results appear | | |
| 5.3 | Click search result | Navigates to entry | | |

---

### 6. Lite Mode Info Modal

**Goal:** Verify subsequent-launch modal works (if preference enabled).

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 6.1 | Quit and relaunch Contextify | App opens | | |
| 6.2 | Check for Lite Mode info modal | Modal appears (if not dismissed previously) | | |
| 6.3 | Dismiss modal | Modal closes, app usable | | |
| 6.4 | Check "Don't show again" option | Preference respected on next launch | | |

---

### 7. Negative Tests (Features Should Be Disabled)

**Goal:** Verify LLM features are properly disabled, not broken.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 7.1 | Check LLM queue polling in logs | Should see "Lite mode - queue polling disabled" | | |
| 7.2 | Right-click timeline entry | No "Copy Summary" option (or shows fallback) | | |
| 7.3 | Monitor Console for 60 seconds | No LLM-related errors or queue activity | | |

---

### 8. Console Log Review

**Goal:** Final review of logs for any errors.

| # | Test Step | Expected | Actual | P/F |
|---|-----------|----------|--------|-----|
| 8.1 | Filter Console by ERROR level | No errors from Contextify | | |
| 8.2 | Search for "crash" or "exception" | None found | | |
| 8.3 | Search for "FoundationModels" | None found (should not attempt to load) | | |
| 8.4 | Search for "dyld" errors | None found | | |

---

## Test Results Summary

| Category | Total | Pass | Fail |
|----------|-------|------|------|
| 1. App Launch | 3 | | |
| 2. Status Bar | 3 | | |
| 3. Timeline Display | 5 | | |
| 4. Core Functionality | 6 | | |
| 5. Search | 3 | | |
| 6. Lite Mode Modal | 4 | | |
| 7. Negative Tests | 3 | | |
| 8. Console Logs | 4 | | |
| **TOTAL** | **31** | | |

---

## Sign-Off

**Tester:** _______________
**Date:** _______________
**VM macOS Version:** _______________
**Contextify Version:** _______________
**Build Type:** [ ] DMG  [ ] App Store

**Result:** [ ] PASS - Ready to merge  [ ] FAIL - See notes

**Notes:**
```


```

---

## If Tests Fail

1. **Capture logs:** Export Console logs for the test session
2. **Screenshot:** Capture any visual issues
3. **Document:** Note exact steps to reproduce
4. **File:** Create issue or update TODOS.md with findings
5. **Do NOT merge** `feature/legacy-macos-support` until all tests pass
