# Lite Mode QA Checklist

**Purpose:** Validate Contextify Lite Mode functionality on macOS 15 (Sequoia).
**When to Run:** Before merging `feature/legacy-macos-support` or any changes affecting lite mode detection.
**VM Setup:** See `macos-vm-setup.md`

---

## Pre-Test Setup

- [ ] macOS 15 VM running (see `macos-vm-setup.md`)
- [ ] Contextify installed on VM (via shared folder or DMG)
- [ ] Test transcripts seeded (run `vm-bootstrap.sh`)
- [ ] Console.app open, filtered to `process:Contextify`

---

## Test Suite

### 1. App Launch (Critical)

**Goal:** Verify app launches without dyld crash.

| # | Test Step | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 1.1 | Launch Contextify from Applications | App opens, no crash | |
| 1.2 | Check Console for dyld errors | None present | |
| 1.3 | Check Console for `[LLM-AVAILABILITY]` | Shows lite mode reason | |

**If 1.1 fails:** The `#if canImport(FoundationModels)` guards are not working. Do not proceed.

---

### 2. Status Bar Display

**Goal:** Verify status bar shows correct lite mode state.

| # | Test Step | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 2.1 | Look at status bar (bottom of HUD) | Shows "Lite Mode" text | |
| 2.2 | Hover over "Lite Mode" | Tooltip shows reason (e.g., "Requires macOS 26") | |
| 2.3 | Click (i) info button | Popover shows detailed explanation | |

---

### 3. Timeline Display

**Goal:** Verify timeline shows entries with appropriate fallback content.

| # | Test Step | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 3.1 | View timeline with seeded transcripts | Entries display without crash | |
| 3.2 | Check user message format | Shows "User: [action label]" | |
| 3.3 | Check assistant message format | Shows "Assistant: [action label]" | |
| 3.4 | Check raw content preview | Shows first ~100 chars of message | |
| 3.5 | Click to expand entry | Shows full untruncated content | |

---

### 4. Core Functionality

**Goal:** Verify non-LLM features work normally.

| # | Test Step | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 4.1 | Switch between projects (if multiple) | Project switch works | |
| 4.2 | Scroll timeline up/down | Smooth scrolling, no crashes | |
| 4.3 | Open Settings | Settings window opens | |
| 4.4 | Open Transcripts window | Window opens, lists transcripts | |
| 4.5 | Open Projects window | Window opens, lists projects | |

---

### 5. Transcript Detail View

**Goal:** Verify transcript detail shows lite mode state correctly.

| # | Test Step | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 5.1 | Open Transcripts window | Window opens | |
| 5.2 | Select a transcript | Detail view shows | |
| 5.3 | Check AI Summary section | Shows "Lite Mode: [reason]" | |
| 5.4 | Verify no "Regenerate" button | Button hidden in lite mode | |

---

### 6. Console Log Review

**Goal:** Final review of logs for any errors.

| # | Test Step | Expected | Pass/Fail |
|---|-----------|----------|-----------|
| 6.1 | Filter Console by ERROR level | No errors from Contextify | |
| 6.2 | Search for "crash" or "exception" | None found | |
| 6.3 | Search for "FoundationModels" | None found (should not attempt to load) | |
| 6.4 | Search for "dyld" errors | None found | |

---

## Test Results Summary

| Category | Total | Pass | Fail |
|----------|-------|------|------|
| 1. App Launch | 3 | | |
| 2. Status Bar | 3 | | |
| 3. Timeline | 5 | | |
| 4. Core Functionality | 5 | | |
| 5. Transcript Detail | 4 | | |
| 6. Console Logs | 4 | | |
| **TOTAL** | **24** | | |

---

## Sign-Off

**Tester:** _______________
**Date:** _______________
**VM macOS Version:** _______________
**Contextify Version:** _______________

**Result:** [ ] PASS - Ready to merge  [ ] FAIL - See notes

**Notes:**
```


```

---

## If Tests Fail

1. **Capture logs:** Export Console logs for the test session
2. **Screenshot:** Capture any visual issues
3. **Document:** Note exact steps to reproduce
4. **File:** Update TODOS.md with findings
5. **Do NOT merge** `feature/legacy-macos-support` until all tests pass
