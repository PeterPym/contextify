---
todo_id: QA-14-APPSTORE-CLI-REPAIR
title: QA-14 App Store CLI repair E2E test plan
type: plan
date: 2025-12-14
status: active
description: Adds deterministic E2E coverage for the App Store Settings → CLI “Repair (Saved Folder)” flow without relying on brittle NSOpenPanel automation.
---

# QA-14: App Store CLI repair E2E

## Goal

Add an automated E2E test that validates the App Store build can repair/reinstall the `contextify-query` shim into a previously authorized folder via Settings → CLI → “Repair (Saved Folder)”.

The test asserts:
- deterministic log tags (`[QUERYCLI-...]`) and
- filesystem side effects (shim present in chosen folder),
without depending on fragile UI traversal.

## Constraints

- The “Choose Install Folder…” action triggers `NSOpenPanel`. System Events automation for open panels is brittle and environment-dependent.
- The App Store flow depends on a security-scoped bookmark saved in preferences.
- The QA suite should avoid privileged writes (`/opt/homebrew/bin`, `/usr/local/bin`).

## Approach

### A) Make “repair” testable without driving NSOpenPanel

Add a QA-only hook that seeds the sandbox install folder bookmark deterministically.

Options:
1. **UserDefaults + bookmark seeding helper in-app (preferred):**
   - A debug-only code path reads a folder URL override and writes the security-scoped bookmark using the same bookmark store as the installer.
   - The E2E script sets the override before launching the app.
2. **One-time manual precondition (acceptable but weaker automation):**
   - Document a one-time manual step to click “Choose Install Folder…” and pick a folder.
   - The E2E test only covers “Repair (Saved Folder)” thereafter.

### B) E2E script flow

File: `scripts/qa/tests/QA-14-cli-install-appstore.sh`

1. Build App Store app (precondition; suite already supports).
2. Ensure Terminal has Accessibility permission (suite already documents).
3. Start log capture.
4. Launch App Store app.
5. Open Settings (Cmd+,).
6. Select the CLI tab (use the same Settings tab override pattern as QA-13 if needed).
7. Click “Repair (Saved Folder)”.
8. Assert logs:
   - `[QUERYCLI-SETTINGS-TAB-OPEN]`
   - `[QUERYCLI-INSTALL-START] mode=appstore action=repairSavedFolder`
   - `[QUERYCLI-INSTALL-DONE] ...` (or a contract-defined failure tag)
9. Assert filesystem: `contextify-query` exists in the authorized folder and is executable.

## Acceptance criteria

- Test passes on a clean machine after the bookmark precondition is met (either seeded via hook or performed once manually).
- Test does not require window counting.
- Failures show actionable diagnostics (log excerpt + paths + any captured stderr).

