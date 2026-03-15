# E2E UI Automation Playbook

Last Updated: 2025-12-14

Contextify’s E2E harness (`scripts/qa/`) relies on OSLog capture plus AppleScript/System Events UI automation. This playbook records patterns that make tests stable and debuggable, based on implementing the Phase 2 “CLI install + skills” E2E coverage.

## Goals

- Prefer deterministic log-tag assertions (`[TAG]`) over UI tree inspection.
- Keep UI automation resilient to SwiftUI accessibility quirks.
- Avoid privileged operations in unattended runs.
- Make failures self-diagnosing (logs + captured stderr + artifact paths).

## Product Policy: Build Breadcrumbs In

User-facing UI should not force automation to guess.

Every new settings pane, sheet, onboarding step, or modal flow should ship with:
- meaningful accessibility labels and hints for actionable controls
- deterministic keyboard navigation through all actionable controls, including buttons in dialog footers
- visible selected-state breadcrumbs for tabs and mode switches
- textual status labels instead of color-only indicators

When SwiftUI still hides control names or selection state from `System Events`, add the narrowest possible QA hook or defaults override instead of accepting brittle coordinate clicking.

## Primary Assertion Strategy: Logs First

- Emit bracketed tags in important state changes and action boundaries (at `.info`).
  - Example tags used by the CLI install UI: `[QUERYCLI-SETTINGS-TAB-OPEN]`, `[QUERYCLI-INSTALL-START]`, `[QUERYCLI-INSTALL-DONE]`, `[QUERYCLI-UNINSTALL-DONE]`.
- E2E scripts should:
  - `wait_for_log_pattern` for readiness,
  - then perform UI actions,
  - then assert a small number of success/failure tags.
- Avoid window counting as a primary signal. Window counts are brittle and do not validate side effects.

References:
- `build/docs/guides/logging-best-practices.md` (E2E-testable logging conventions)
- `scripts/qa/lib/common.sh` and `scripts/qa/lib/assertions.sh` (log capture + assertions)

## AppleScript/System Events: SwiftUI Reality Checks

SwiftUI often exposes incomplete accessibility metadata to System Events:

- Button titles may be present visually but `name of button …` returns `missing value`.
- Window-level “buttons” typically include only chrome (close/minimize/zoom), not content.
- Content buttons are frequently nested under groups (e.g. `group 1 of group 1 of window "CLI"`).
- Tabs in a SwiftUI `TabView` can appear as unnamed `toolbar` buttons.

### Prefer navigation hooks over tree traversal

When tests need a specific state (e.g. “Settings open on the CLI tab”), avoid fragile UI selection:

- Prefer keyboard shortcuts (`Cmd+,`, `Enter`, explicit shortcuts) when possible.
- If keyboard navigation is not possible, use small QA-only hooks that set state directly.
- If the feature is new, fix the missing breadcrumb in product code rather than teaching automation a brittle workaround and walking away.

## Keyboard-First UI Automation Patterns

### Default action (Enter) for primary button

Onboarding tests are stable because they can:
- `press_return` to trigger the default action, then
- `press_return` again to accept `NSOpenPanel` defaults.

Pattern:
- In SwiftUI, apply `.keyboardShortcut(.defaultAction)` to the primary button in a flow.
- In E2E, prefer `press_return` over clicking nested buttons.

Example:
- `scripts/qa/tests/QA-01c-launch-appstore-clean.sh` uses `press_return` for onboarding navigation.

### Explicit keyboard shortcuts for secondary actions

For actions that are not reliably reachable by default action (e.g. uninstall), prefer stable explicit shortcuts. A test can then use:
- `send_shortcut "u" "command down, shift down"`

The UI should still remain usable for humans; shortcuts are additive.

## QA-Only UserDefaults Hooks (Narrow Scope)

Some flows cannot be reliably automated without either:
- clicking nested SwiftUI controls with missing accessibility metadata, or
- interacting with privilege-gated filesystem locations.

Prefer a narrowly-scoped UserDefaults hook over brittle UI element traversal or `sudo` in tests.

### CLI install directory override

Problem:
- DMG “Install/Repair (Recommended)” naturally prefers `/opt/homebrew/bin` or `/usr/local/bin`, which may require `sudo` and is not deterministic in an E2E environment.

Solution:
- Provide a QA-only override key that forces a deterministic install directory (e.g. `/tmp/contextify-qa-bin`) for unattended tests.

Usage (shell):
- `defaults write dev.contextify Contextify.QueryCLI.DMGInstallDirOverride -string /tmp/contextify-qa-bin`

### Settings tab selection override

Problem:
- Selecting the correct Settings tab via AppleScript can be brittle when tabs appear as unnamed toolbar buttons.

Solution:
- Provide a QA-only override key that forces Settings to open on a specific tab.

Usage (shell):
- `defaults write dev.contextify Contextify.Settings.SelectedTabOverride -string cli`

## Default Domain for Automation Keys

Contextify prefers a shared defaults suite (`dev.contextify`) when writable, so automation and runbooks can set keys consistently across distributions.

Guidelines:
- Tests should write overrides to `dev.contextify` unless explicitly testing the app’s sandbox container defaults.
- App-side code that needs to read automation overrides should read from the same shared defaults selection used elsewhere (not `UserDefaults.standard` directly).

## Debugging Tips for E2E Failures

### When log capture works but a UI action “does nothing”

- Confirm the window is actually in the expected state by asserting a “tab open” log tag (or add one).
- If the action is expected to emit `[TAG]-START`, assert that tag first before waiting for completion.
- If a click succeeds in AppleScript but no logs appear, the click likely targeted a different element (or an element that does not map to the intended action).

### App Store build: embedded CLI may not be runnable standalone

In the current Phase 2 implementation, `contextify-query` embedded in the App Store build can terminate at process startup (e.g. `SIGTRAP` / exit `133`) due to sandbox initialization.

Implications:
- E2E tests that validate “the shim runs the CLI and returns JSON” should force the **DMG** app bundle explicitly (see `CONTEXTIFY_QUERY_APP_PATH` below) on machines that have both DMG and App Store builds present.
- Prefer log-tag assertions + filesystem side effects for App Store flows unless/until the embedded CLI is safe to execute outside the app.

### Capture stderr for subprocess assertions

If E2E runs a tool and expects JSON:
- capture stderr to an artifact file under `LOGDIR`
- include both stdout and stderr in the failure report

This prevents “empty JSON” errors from hiding the real cause.

### Avoid shell builtin collisions

In some shells, `log` can be a builtin. Prefer calling `/usr/bin/log` explicitly from scripts when using `log show`.

## Multi-Install Environments and “Shim picks wrong app”

Systems can have multiple Contextify installs (DMG builds, App Store builds, archived `.xcarchive` products, mounted volumes).

For the PATH shim (`contextify-query` shim binary), candidate selection should remain deterministic and should bias toward the install that can actually execute the bundled CLI.

Recommended selection precedence:
- Prefer candidates that contain an executable bundled CLI (`Contents/MacOS/contextify-query`)
- Then prefer App Store installs (receipt present) when ties exist
- Then prefer highest `CFBundleVersion` / `CFBundleShortVersionString`
- Then deterministic path tiebreak

This prevents the shim from selecting an install that cannot run `contextify-query`.

### Forcing the shim to a specific app bundle (QA/debug)

When validating shim behavior in a multi-install environment, set:

- `CONTEXTIFY_QUERY_APP_PATH=/path/to/Contextify.app`

This forces the shim to exec `Contents/MacOS/contextify-query` from that bundle (and avoids “picked the wrong install” failures).

## Concrete AppleScript selectors that worked

- Settings tabs as toolbar buttons (DMG build): `click button 2 of toolbar 1 of window 1` selects the CLI tab.

## Documentation to Keep Updated

- `build/docs/guides/logging-best-practices.md`: keep an “E2E-Friendly UI Patterns” section current.
- `scripts/qa/README.md`: document QA-only defaults overrides and any required one-time system setup (e.g. Terminal Accessibility).
- `build/docs/guides/feature-development-workflow.md`: require `[TAG]` logs and E2E additions for user-facing flows.
