---
todo_id: CONTEXTIFY-QUERY-APPSTORE-CLI
title: App Store embedded contextify-query standalone execution investigation
type: investigation
date: 2025-12-14
status: active
description: Determines whether the embedded contextify-query binary in App Store builds is expected to run as a standalone CLI tool and, if so, what changes are required to make it stable.
---

# App Store embedded `contextify-query` standalone execution

## Current behavior

On a dev machine that has both DMG and App Store builds, running:

- `<AppStore Contextify.app>/Contents/MacOS/contextify-query --help`
- `<AppStore Contextify.app>/Contents/MacOS/contextify-query status --json`

can terminate at process startup with `SIGTRAP` / exit code `133` before emitting JSON.

This appears to occur during sandbox initialization (before app code runs).

## Why it matters

- The Phase 2 UX installs a PATH shim that execs `Contents/MacOS/contextify-query` from the selected Contextify bundle.
- If the shim selects an App Store build, the user may get a non-actionable failure when invoking `contextify-query`.
- E2E tests that validate shim behavior must avoid accidentally executing the App Store embedded CLI.

## Decision to make

Choose one:

1. **Standalone is supported (preferred long-term):**
   - `contextify-query` runs reliably when executed outside the app, in both DMG and App Store distributions.
   - The tool uses the same permission model as the app (e.g. security-scoped bookmarks) or a documented user flow.
2. **Standalone is not supported (acceptable for Phase 2):**
   - The shim must deterministically select the DMG build for PATH usage, or the product messaging must make App Store constraints explicit.
   - Skills must be able to call an absolute path into the app bundle or use an in-app bridge.

## Immediate mitigations already in place

- E2E and debugging can force the shim to a specific app bundle via `CONTEXTIFY_QUERY_APP_PATH=/path/to/Contextify.app`.
- The shim selection prefers candidates that actually contain an executable bundled CLI.

## Next investigative steps

- Confirm whether `contextify-query` in the App Store build is expected to be sandboxed as an app-like binary or should be unsigned/unsandboxed (and whether that is permitted).
- Determine if the crash is due to:
  - missing `CFBundleIdentifier`/bundle metadata in code signature context for a standalone tool,
  - invalid container resolution for a nested executable,
  - an entitlement mismatch for a non-app Mach-O launched from Terminal.
- Reproduce in isolation:
  - Run the App Store embedded `contextify-query` directly.
  - Run it via the PATH shim selecting the App Store bundle.
  - Compare with running the DMG embedded `contextify-query`.
- Document the supported model in the Phase 2 spec once the decision is made.

