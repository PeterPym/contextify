---
feature: menubar-background-mode
branch: ct-429-menubar-background-mode
date: 2026-03-15
status: ready-for-merge
---

# Menu Bar / Background Utility Mode - Validation Plan

This document tracks validation for menu bar extra and background utility mode
transitions introduced in ct-429 (Phase 2: ct-458).

**QA Script:** [`interactive-qa.sh`](./interactive-qa.sh)

---

## Testable Scenarios

### S1: Launch in normal mode (both prefs OFF)
**Automatable:** Partially (can verify process running and pref state; Dock/window checks require visual confirmation or Accessibility scripting)

- [ ] Main window appears
- [ ] Dock icon present
- [ ] Command-Tab presence
- [ ] No menu bar extra icon

### S2: Launch in utility (background) mode
**Automatable:** Partially (same constraints as S1)

- [ ] No window flash on launch
- [ ] No Dock presence
- [ ] No Command-Tab presence
- [ ] Menu bar extra icon present

### S3: Close main window in utility mode
**Automatable:** Partially (window close via AppleScript, but Dock observation needs visual check)

- [ ] Main window opens from menu bar extra
- [ ] After closing window, Dock icon disappears
- [ ] Menu bar extra remains
- [ ] App continues running (not quit)

### S4: Reopen main window from menu bar
**Automatable:** Partially (can script the click, visual confirmation needed)

- [ ] Window reappears from menu bar extra action
- [ ] App activates (comes to front)
- [ ] Dock icon reappears

### S5: Quit and relaunch with utility mode enabled
**Automatable:** Yes (pref persistence is deterministic, launch behavior is observable via process/log checks)

- [ ] Preferences persist across quit/relaunch
- [ ] Main window does NOT appear after relaunch
- [ ] No Dock presence after relaunch
- [ ] Menu bar extra present after relaunch

### S6: Toggle utility mode ON while running
**Automatable:** Partially (pref write + observe via Accessibility or log)

- [ ] Menu bar extra appears when enabling utility mode
- [ ] Main window persists (already open)
- [ ] After closing all windows, Dock icon disappears

### S7: Toggle utility mode OFF while running
**Automatable:** Partially

- [ ] Dock icon reappears when disabling utility mode
- [ ] Command-Tab presence restored

### S8: Toggle menu bar extra ON/OFF independently
**Automatable:** Partially (pref write + status item observation)

- [ ] Menu bar extra appears when toggled on
- [ ] Menu bar extra disappears when toggled off

### S9: Open Settings from popover (utility mode)
**Automatable:** Difficult (popover is outside SwiftUI scene graph; System Events scripting is fragile)

- [ ] Settings window opens from popover in utility mode
- [ ] App activates and Dock icon appears
- [ ] Popover closes automatically after action

### S10: Popover dismiss behavior
**Automatable:** Difficult (requires click-coordinate scripting)

- [ ] Popover opens on status item click
- [ ] Popover dismisses on outside click
- [ ] Popover toggles on repeated status item clicks

### S11: Close Settings while main window still open (utility mode)
**Automatable:** Partially (activation policy observable via OSLog `[POLICY]` tags)

- [ ] Open main window + Settings while in utility mode
- [ ] Close Settings; Dock icon persists (main window still visible)
- [ ] Close main window; Dock icon then disappears

### S12: Keep on Top + Settings window elevation
**Automatable:** No (window z-order requires visual confirmation)

- [ ] Enabling Keep on Top floats main window above other apps
- [ ] Settings window appears above the floating main window (not behind it)
- [ ] Disabling Keep on Top restores normal window level

---

## Automation Breadcrumbs

The following accessibility identifiers and labels are available for automation:

### Settings > General Tab
| Element | Identifier | Label |
|---------|-----------|-------|
| Menu bar extra toggle | `general-menu-bar-extra-toggle` | "Show menu bar extra" |
| Background utility toggle | `general-background-utility-toggle` | "Run as background utility" |
| Utility mode status text | `general-background-utility-status` | (dynamic text) |

### Status Item Popover
| Element | Identifier | Label |
|---------|-----------|-------|
| Popover container | `menubar-popover-content` | -- |
| Status text | `menubar-popover-status` | (dynamic) |
| Show/Hide Main Window button | `menubar-popover-toggle-main` | "Show Main Window" / "Hide Main Window" |
| Settings button | `menubar-popover-settings` | "Open Settings" |
| Quit button | `menubar-popover-quit` | "Quit Contextify" |

### Menu Bar Status Item
| Element | Note |
|---------|------|
| NSStatusItem button | Standard AppKit; accessible via System Events as menu bar item of process "Contextify" (menu bar 2) |
| Button tooltip | Set to `presentation.statusText` (dynamic) |
| Button accessibility description | "Contextify" |

### OSLog Tags (for log-based assertion)
| Tag | Meaning |
|-----|---------|
| `[STATUS-ITEM] Created NSStatusItem` | Status item was shown |
| `[STATUS-ITEM] Removed NSStatusItem` | Status item was hidden |
| `[STATUS-ITEM] Popover shown` | Popover opened |
| `[STATUS-ITEM] Popover dismissed` | Popover closed |
| `[POLICY] Setting activation policy to .regular` | Switched to regular (Dock visible) |
| `[POLICY] Setting activation policy to .accessory` | Switched to accessory (Dock hidden) |
| `[POLICY] Promoting to .regular for` | Temporary promotion for window |
| `[POLICY] Window change -> switching to` | Policy change after window close/open |

---

## Non-Automatable Gaps

### 1. Dock Icon Visual Presence
**Why:** `NSApplication.activationPolicy` can be queried programmatically, but the
Dock icon animation and visual removal happen asynchronously. System Events can
detect whether a process is "visible," but the mapping is not always reliable
for accessory-policy apps.

**QA Hook:** The interactive QA script asks the tester to visually confirm. For
CI, the closest proxy is checking OSLog for `[POLICY]` tags that confirm the
activation policy was set.

### 2. Command-Tab Switcher Presence
**Why:** There is no public API to query the Command-Tab application list. It
mirrors `activationPolicy`, so log-based verification of `.accessory` vs
`.regular` is the best proxy.

**QA Hook:** Same as above: OSLog `[POLICY]` tags.

### 3. Window Flash on Launch
**Why:** Verifying that a window does NOT briefly flash requires pixel-level
observation or very precise timing checks. The implementation uses
`orderOut(nil)` on the next run loop, so any flash would be < 16ms.

**QA Hook:** The interactive QA script asks for visual confirmation. OSLog for
`registerMainWindow` could be checked to confirm the orderOut path was taken.

### 4. Popover Content Interaction
**Why:** The NSPopover is hosted via NSHostingController outside the SwiftUI
scene graph. System Events can see the popover as a window, but individual
SwiftUI buttons inside it are not reliably addressable via AppleScript.

**QA Hook:** Accessibility identifiers are set on all popover buttons. XCUITest
or Accessibility Inspector can query them. The interactive QA script relies on
manual interaction.

---

## Build Variants

### DMG Build (Primary)
All scenarios are testable with the DMG build. The DMG build has no sandbox
restrictions, so file access and preference writes work directly.

### App Store Build
The same mode-transition behavior should work identically in the App Store build.
The activation policy APIs and NSStatusItem APIs are not affected by the sandbox.
However, the App Store build uses a different bundle ID (`sh.contextify.Contextify`)
and a different defaults domain, so preference manipulation in the QA script would
need adjustment.

**Recommendation:** Run the interactive QA script with the DMG build. If App Store
parity is needed, modify `DEFAULTS_DOMAIN` and `DMG_APP_PATH` in the script or
test manually.

---

## Related Files

- **QA Script:** `scripts/qa/menubar-mode/interactive-qa.sh`
- **AppPresentationController:** `Contextify/Contextify/AppPresentationController.swift`
- **StatusItemController:** `Contextify/Contextify/StatusItemController.swift`
- **GeneralSettingsView:** `Contextify/Contextify/Settings/GeneralSettingsView.swift`
- **MenuBarExtraContent:** `Contextify/Contextify/MenuBarExtraContent.swift`
- **Popover Content:** `StatusItemPopoverContent` (in StatusItemController.swift)
- **Preferences:** `app/Sources/ContextifyCore/HUDCore.swift` (keys + helpers)
- **Presentation Logic:** `app/Sources/ContextifyCore/MenuBarStatus.swift`
- **Unit Tests:** `Tests/ContextifyCoreTests/MenuBarStatusTests.swift`
