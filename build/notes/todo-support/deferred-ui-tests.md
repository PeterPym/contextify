---
title: Deferred UI Tests Registry
type: plan
date: 2025-11-24
status: active
description: Catalog of UI behavior we can’t yet cover with SPM tests; each entry records context, verification steps, and supporting artifacts (logs, DB queries).
---

## 1. Timeline summary queueing needs a viewport test

**Problem:** After switching to `webviewer` (see `/private/tmp/transcript-queue-monitor-20251124-110308.log`), the visible entries (IDs `f9d9b1c7`, `a796c993`, `d6b8470e`, etc.) remain in “hourglass” state even though the viewport never scrolls. Queueing only runs once the fallback timer fires (`[SUMM-VIEWPORT-FALLBACK]` around `11:03:11`, `[SUMM-QUEUE-NEEDS-SUMMARY-COUNT] = 17`), and then pruning immediately removes entries that are no longer in `lastVisibleIDs`. This leaves the topmost messages unsummarized.

**Verification steps:**
1. Launch the app, switch to the `webviewer` project with `Contextify`.
2. Capture logs with `scripts/logging/monitor-viewport-queueing.sh` (or similar) while *not* manually scrolling.
3. Look for these log patterns within ~1s of the switch:
   - `[SUMM-LOAD-DEFER] Deferring queueing to viewport tracking`
   - `[SUMM-VIEWPORT-FALLBACK] ... firing in 500ms`
   - `[SUMM-PRUNE-*]` showing queue depth and removed items
   - `[SUMM-QUEUE-*]` showing visible IDs being re-queued (should execute even without `isUserScrollActive`)
4. Confirm the fallback path fires only once (not repeatedly) and that queueing runs even without a scroll event.

**Supporting DB queries:**
- List visible entries and re-check their summary/cache state:
  ```sql
  SELECT id, content, window_sha256 FROM transcript_entries
  WHERE project_id = '-Users-rob-code-projects-webviewer'
    AND timestamp BETWEEN strftime('%s','2025-11-01T06:48:00Z') AND strftime('%s','2025-11-01T06:50:30Z');
  ```
- Determine which entries still lack cached summaries:
  ```sql
  SELECT entry_id FROM timeline_cache WHERE entry_id IN (<visible IDs>);
  ```
- Check queue flags:
  ```sql
  SELECT entry_id, is_queued FROM transcript_entries WHERE entry_id IN (<visible IDs>);
  ```

**Goal:** Build an automated UI test (or instrumentation) that ensures the viewport-triggered queue path executes without requiring user scrolls and that entries in the initial viewport reach the LLM queue without being pruned away first. Recording the log/DB queries above will help validate this behavior before converting to a fully automated regression test.

## 2. Empty-project spinner avoidance needs UI coverage

**Problem:** We added logic so `ConversationMonitor` skips `.loading` when a project has zero entries, but the UI test harness can't currently reproduce the spinner branch to verify the empty state renders immediately. SwiftUI automation is fragile (TableView/timeline flicker, placeholder states), so there isn’t a reliable `swift test` that exercises the spinner vs empty-state branch.

**Verification hints:**
1. Manually switch to a project known to have no entries (e.g., a fresh repo) and confirm the HUD shows “No Activity Yet” instantly instead of the spinner.
2. Capture logs (`[TIMELINE-LOAD]`, `[TIMELINE-HYDRATE-SKIP]`, and `[TIMELINE-LOAD] primer complete` showing phase transitions) to prove the monitor reported zero entries.
3. Use SQL to confirm the project has no `timeline_entries` but does exist (e.g., `SELECT COUNT(*) FROM transcript_entries WHERE project_id = '<id>'` returns 0).

**Goal:** Add the empty-state UI test once the SwiftUI automation stabilizes (or move this check into a lightweight expectation harness) so we can guard the spinner-free behavior. Keep this entry in the deferred doc until the automated test is written.

## 3. Initial viewport fallback handshake needs verification

**Problem:** In the `commands`/`webviewer` timeline the spinner was previously stuck because `[SUMM-VIEWPORT-FALLBACK]` re-armed after the first viewport snapshot even though no scroll occurred. The fix introduces instrumentation (`[SUMM-VIEWPORT-ACCEPTED]`, `[SUMM-VIEWPORT-STARVATION]`, `initial_viewport_fallback_*` counters) but we still lack a SwiftUI automation that captures the UI state and correlates it with the logs.

**Verification steps:**
1. Launch the HUD and switch to the `commands` project while **not** manually scrolling.
2. Capture logs around the switch and confirm the following sequence fires exactly once:
   - `[SUMM-LOAD-STATE] ... needsInitialSnapshot=true`
   - `[SUMM-VIEWPORT-ACCEPTED] ... initial viewport snapshot`
   - `[SUMM-VIEWPORT-FALLBACK]` (should not fire or should skip re-queue; fallback count should stay at 1)
   - `[SUMM-VIEWPORT-STARVATION]` should not log for this scenario
3. Ensure the visible entries go from the hourglass/pending state to summarized within a few seconds (use the status bar or dedicated UI flags rather than scrolling).
4. Re-check the timeline entries in SQLite to verify the `is_queued` flag transitions to `1` for the visible entries that were pending.

**Goal:** Build a deferred SwiftUI test that asserts the HUD transitions out of the spinner state for non-scrolling projects while the instrumentation above stays within expected bounds. Until the SwiftUI harness can reliably reproduce this scenario, the above steps and log checks remain the verification checklist.

## 4. CLI Admin Install Dialog (DMG Non-Homebrew Users)

**Problem:** The admin install dialog flow requires real admin password entry and system-level permissions (osascript with administrator privileges). Cannot be automated in CI/E2E tests because:
- Requires actual user password input
- Needs `sudo` privileges to verify file ownership
- Environment setup (making `/opt/homebrew/bin` and `/usr/local/bin` non-writable) is destructive

**Why admin install is needed:** For DMG builds on systems without homebrew (or where homebrew paths are owned by root), the CLI shim cannot be installed to writable system paths. The app offers admin install to `/usr/local/bin` as an alternative to `~/bin` (which requires manual PATH configuration).

**Verification steps:**

1. **Mock non-homebrew environment:**
   ```bash
   sudo chown root:wheel /opt/homebrew/bin /usr/local/bin
   ```

2. **Clean existing CLI installation:**
   ```bash
   rm -f /opt/homebrew/bin/contextify-query 2>/dev/null || true
   rm -f /usr/local/bin/contextify-query 2>/dev/null || true
   rm -rf ~/.claude/plugins/cache/contextify 2>/dev/null || true
   ```

3. **Launch app and navigate to Settings > CLI:**
   ```bash
   ./scripts/xc.sh dr  # Clean run
   ```
   - App should launch with CLI disabled (no auto-install for non-homebrew)
   - Go to Settings > CLI tab
   - Should show "Not installed" with blue "Enable" button

4. **Test admin install success:**
   - Click "Enable"
   - **Verify dialog appears** with:
     - Title: "Administrator Access Required"
     - Message: "Contextify will request administrator privileges to install the 'contextify-query' command to /usr/local/bin."
     - Additional paragraph: "The request to make changes will come from 'osascript'. This one-time access is used solely to add the contextify-query command to your system path."
     - Two buttons: "Install" (blue) and "Cancel" (gray)
   - Click "Install"
   - **Enter admin password** in system prompt
   - Should show "Installing..." briefly with spinner
   - Should transition to "Installed (v{VERSION})" with green checkmark

5. **Verify installation:**
   ```bash
   # Check file exists and is an actual executable (not symlink)
   ls -la /usr/local/bin/contextify-query
   # Should show: -rwxr-xr-x  1 root  wheel  149312 ... (actual file)

   # Verify it's a Mach-O executable
   file /usr/local/bin/contextify-query
   # Should show: Mach-O 64-bit executable arm64

   # Test executable works
   /usr/local/bin/contextify-query --version
   # Should run without errors
   ```

6. **Test cancellation handling (dialog cancel):**
   - Disable CLI in Settings
   - Click "Enable" again
   - Click "Cancel" in admin dialog
   - Should show "Installation cancelled" message
   - "Enable" button should still be available (can retry)

7. **Test cancellation handling (password cancel):**
   - Click "Enable" again
   - Click "Install" in admin dialog
   - **Cancel the password prompt** (macOS system dialog)
   - Should show "Installation cancelled" (NOT technical error message)
   - "Enable" button should still be available (can retry)

8. **Test disable/re-enable:**
   - With CLI installed via admin, click "Disable"
   - Verify `/usr/local/bin/contextify-query` is removed
   - Click "Enable" again
   - Should show dialog and allow reinstall

9. **Cleanup (restore permissions):**
   ```bash
   sudo chown $(whoami):admin /opt/homebrew/bin /usr/local/bin
   ```

**Expected log sequence (success case):**
```
[CLI-ENABLE-START]
[CLI-NO-WRITABLE-PATHS] Requesting admin install
[CLI-ADMIN-DIALOG-APPROVED]
[CLI-ADMIN-INSTALL-START] destination=/usr/local/bin/contextify-query
[CLI-ADMIN-INSTALL-SUCCESS]
[CLI-INSTALL-SUCCESS] shim=/usr/local/bin/contextify-query plugin=...
[CLI-ENABLE-SUCCESS]
```

**Expected log sequence (user cancelled password):**
```
[CLI-ENABLE-START]
[CLI-NO-WRITABLE-PATHS] Requesting admin install
[CLI-ADMIN-DIALOG-APPROVED]
[CLI-ADMIN-INSTALL-START]
[CLI-ADMIN-INSTALL-CANCELLED]
[CLI-ENABLE-FAILED] error=Installation cancelled
```

**Common issues to watch for:**
- Broken symlink instead of actual file (old bug: should see `-rwxr-xr-x` not `lrwxr-xr-x`)
- Technical error message on password cancel (should show "Installation cancelled")
- Dialog appearing during auto-install instead of only when user clicks Enable
- PATH warning showing for admin-installed CLI (should NOT show - /usr/local/bin is always on PATH)

**Goal:** This test cannot be automated because it requires real user interaction (password entry). Keep this manual QA procedure for pre-release testing and when making changes to the admin install flow. The automated E2E test (`scripts/qa/tests/QA-13b-cli-install-admin-fallback.sh`) validates log tags and the ~/bin fallback path but cannot test the actual admin install.

## 5. CLI Install in App Store Build (Regression Check)

**Problem:** App Store builds are sandboxed and cannot use osascript with administrator privileges. Need to verify that App Store builds NEVER show the admin install dialog and always use `~/bin` installation path.

**Why this is a regression check:** The admin install feature is DMG-only. If the admin dialog accidentally appears in App Store builds, it indicates a bug in the sandbox detection logic.

**Verification steps:**

1. **Build App Store version:**
   ```bash
   ./scripts/xc.sh --dist=appstore Debug cleanrun
   ```

2. **Mock non-homebrew environment (same as DMG test):**
   ```bash
   sudo chown root:wheel /opt/homebrew/bin /usr/local/bin
   ```

3. **Clean existing CLI installation:**
   ```bash
   rm -rf ~/.claude/plugins/cache/contextify 2>/dev/null || true
   rm -f ~/bin/contextify-query 2>/dev/null || true
   ```

4. **Complete onboarding** (App Store requires permission grants)

5. **Go to Settings > CLI and click "Enable":**
   - **Should NOT show admin dialog** (this is the key check)
   - Should install directly to `~/bin/contextify-query`
   - **Should show PATH warning** if `~/bin` not on PATH (expected and correct):
     - Warning icon with text: "~/bin is not on your PATH"
     - Instructions: "Add to ~/.zshrc or ~/.bashrc:"
     - Copy button for: `export PATH="$HOME/bin:$PATH"`
     - User can click Copy, paste into shell config, restart terminal

6. **Verify installation:**
   ```bash
   # Check installed to ~/bin (not /usr/local/bin)
   ls -la ~/bin/contextify-query
   # Should show: -rwxr-xr-x ... (owned by user, not root)

   # Verify NOT installed to system paths
   ls -la /usr/local/bin/contextify-query 2>&1
   # Should show: No such file or directory

   # Test executable works
   ~/bin/contextify-query --version
   # Should run without errors
   ```

7. **Cleanup:**
   ```bash
   sudo chown $(whoami):admin /opt/homebrew/bin /usr/local/bin
   ```

**Expected log sequence:**
```
[CLI-ENABLE-START]
[CLI-INSTALL] Starting installation...
[CLI-INSTALL-SUCCESS] shim=/Users/{user}/bin/contextify-query plugin=...
[CLI-ENABLE-SUCCESS]
```

**Should NOT see these tags:**
- `[CLI-NO-WRITABLE-PATHS]` (should not check system paths)
- `[CLI-ADMIN-DIALOG-*]` (dialog should never appear)
- `[CLI-ADMIN-INSTALL-*]` (admin install should never run)

**Critical regression:** If the admin dialog appears in App Store builds, this is a **P0 bug** that must be fixed before release. The sandbox detection (`Sandbox.isSandboxed`) is failing.

**Goal:** Verify App Store builds always use `~/bin` and never attempt admin install. This is a regression check to ensure DMG-specific code doesn't leak into App Store builds.
