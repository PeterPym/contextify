# Contextify — Compose Panel URL Handler (Technical Briefing)

## 1) Purpose & Intended Behavior

**Goal:** Provide a fast, URL-driven “compose” panel that receives text from external triggers (shell keybinding, other apps), lets the user optionally edit it, and then delivers the text to iTerm2 either as keystrokes or by writing to a temp file.

**Primary UX flow**
1. External trigger calls a custom URL, e.g.:
   - `contextify://compose?title=Ping&text=hello%20world`
   - `contextify://compose?title=B64&text64=<base64-url-encoded>`
2. Contextify brings a **single, reusable** compose panel forward.
3. The panel **prefills** with the provided text, **focuses** the editor, caret at end.
4. User clicks:
   - **As keystrokes** → sends to iTerm2 (with newline)
   - **As keystrokes (no newline)** → same, no newline
   - Or, if `tmpfile=/path/to/file` was passed → writes text there and foregrounds iTerm2.
5. Panel hides (not destroyed). Next trigger **reuses** the same panel.

**Secondary goals**
- Avoid multiple app windows and multiple URL handlers.
- Keep SwiftUI/NSPanel lifecycle stable (no crashy dealloc on close).
- Allow Debug/Release to coexist without LaunchServices conflicts via separate schemes.

---

## 2) Current Design & Components

### 2.1 Scene & URL Entry

- Singleton scene via **`Window("Contextify", id: "main")`** (not `WindowGroup`) to prevent accidental multi-window spawns.
- **`AppDelegate`** handles all `application(_:open:)` URL events and routes into the URL router. It also:
  - returns **`false`** from `applicationShouldOpenUntitledFile` and `applicationOpenUntitledFile` to **block** implicit untitled windows.
  - implements `applicationShouldHandleReopen` to bring the single main window forward without creating a new one.
- **`MainWindowTracker`** + `WindowAccessor` capture the actual `NSWindow` for deterministic “bring to front”.

### 2.2 URL Router

- **`ComposeURLRouter.handle(_:)`** parses:
  - `text` (URL-decoded)
  - `text64` (base64, **URL-percent-encoded** prior to base64 decode)
  - `title` (panel title)
  - `tmpfile` (optional write path)
  - `send` (default `true`)
- Accepts **two schemes**:
  - Release: `contextify://...`
  - Debug: `contextify-dev://...`
- Delegates to **`ComposePresenter.present(...)`** → **`ComposeWindowController.present(...)`**.

### 2.3 Compose Window Lifecycle

- **`ComposeWindowController`** (subclass of `NSWindowController`):
  - Owns a **single retained `NSPanel`**, created by `makePanel()`:
    - `.isReleasedWhenClosed = false`
    - `.animationBehavior = .none`
    - `.isFloatingPanel = true`
    - `.collectionBehavior.insert(.moveToActiveSpace)`
  - Replaces ephemeral SwiftUI state with a **shared `ComposeModel` (`ObservableObject`)** bound into the view.
    - On every URL trigger, the controller sets `model.text = <incoming>`, guaranteeing overwrite.
  - Presents by:
    - updating panel title
    - centering on first show
    - **conditionally** activating the app: `if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }`
    - `panel.orderFront(nil); panel.makeKey()` (avoids reorder/flicker)
    - posting `.contextifyFocusEditor` **after 20ms** so the NSTextView becomes first responder and caret moves to end.
  - Close is **converted to hide** (`orderOut(nil)`) via `windowShouldClose` to avoid teardown races.

### 2.4 Editor & Focus

- **`FocusableTextView`** (`NSViewRepresentable`) wraps `NSTextView`:
  - Listens for `.contextifyFocusEditor` and calls `.makeFirstResponder`.
  - Sets selection to end; scrolls caret into view.
  - Two-way binds with the shared `ComposeModel.text`.

### 2.5 iTerm2 Delivery

- **`ITerm2Bridge`** sends text to iTerm2:
  - Either via AppleScript (`write text "..."`) or your AEDesc-based approach.
  - The app is **sandboxed** with `com.apple.security.automation.apple-events` entitlement; TCC will prompt on first use.

### 2.6 Shell Integration

- **`scripts/build/install-shell-bindings.sh`** installs **Ctrl-X Ctrl-K**:
  - `zsh`: sends region if selected; else `$BUFFER`.
  - `bash`: sends the last command line (readline limitation).
  - The payload is **base64 + URL-percent-encoded** to keep `+` and `=` intact.
  - Scheme is parameterized (`contextify` vs `contextify-dev`).

### 2.7 Build & LaunchServices Hygiene

- One derived output path: **`.derived/Build/Products/<CONFIG>/Contextify.app`** via `scripts/xc.sh`.
- **`lsregister`** usage (no `-kill`):
  - Unregister strays: `sudo lsregister -f -u "<path>/Contextify.app"`
  - Register intended: `lsregister -f -R ".derived/Build/Products/Debug/Contextify.app"`
- Debug vs Release split:
  - Debug: `PRODUCT_BUNDLE_IDENTIFIER=PeterPym.Contextify.Debug`, `Info-Debug.plist` claims `contextify-dev`.
  - Release: `PRODUCT_BUNDLE_IDENTIFIER=PeterPym.Contextify`, `Info.plist` claims `contextify`.

---

## 3) Current State (Observed)

- **Panel reuse:** Works. Subsequent URL triggers reuse the same NSPanel instance.
- **Focus & caret:** Works via notification + NSTextView control.
- **Main window duplication:** Addressed by moving from `WindowGroup` → `Window` and blocking AppKit untitled-window creation. If a flicker remains, it indicates an unconditional `NSApp.activate` or another scene attachment—currently guarded.
- **Overwrite behavior:** Now robust due to **shared `ComposeModel`**; `model.text` is **replaced** on every present (no stale `@State`).
- **Shell encoding:** Base64 is URL-encoded; router decodes reliably.

---

## 4) What Might Still Be Needed / Improvements

### 4.1 Robustness & UX
- **Append mode (optional):** support `mode=append` so power users can accumulate:
  - URL: `...&mode=append`
  - Controller: `model.text += incoming`
- **Unsaved draft warning:** If panel has been edited since last present, allow a subtle toast “replaced previous text” with “[Undo]”.
- **Draft history ring:** Keep last N drafts in memory (timestamp, source, title). Provide quick “restore previous” (⌘[) and “next” (⌘]) actions.
- **Panel positioning:** Persist frame; restore on next present (you can store `NSStringFromRect(panel.frame)` in `UserDefaults`).
- **Explicit “bring iTerm after send” toggle:** Panel checkbox that controls post-send app activation (some users prefer staying in Contextify).

### 4.2 LaunchServices & Distribution
- **Guard against stray copies** on developer machines:
  - Add a “Diagnostics → Show registered handlers” command that runs `LSCopyDefaultHandlerForURLScheme` for both schemes and prints paths.
- **Uninstaller for keybinding:** Complement installer with `scripts/uninstall-shell-bindings.sh` that strips the block from rc files.

### 4.3 iTerm2 Bridge
- **Low-level AEDesc path (optional):** Keep AppleScript fallback for portability; wrap both behind the same async API.
- **TCC preflight:** Consider calling `AEDeterminePermissionToAutomateTarget` (if you maintain the AEDesc variant) to surface a clear error when Automation is denied.

### 4.4 Testing & CI
- **Unit tests for router:** Given URLs → assert parsed fields; table-driven tests for `text` vs `text64`, weird edge cases (empty/invalid base64).
- **UI test smoke:** Launch app; programmatically open URL via `NSWorkspace.shared.open(URL)`; verify panel shows and model updates (can expose a test hook).
- **lsregister checks in CI (optional):** Not strictly necessary; local dev script is sufficient.

---

## 5) Known Pitfalls & How We Addressed Them

- **Multiple URL handlers** (Debug/Release both claiming `contextify`) → Use **separate schemes**; unregister strays; explicitly (re)register intended bundle.
- **`open -b ... 'contextify://...'`** unreliable URL delivery → Prefer `open -u 'contextify://...'` to let LS route by scheme.
- **SwiftUI `WindowGroup`** spawning a new base window on URL opens → Use a **singleton `Window`**; handle URLs in **AppDelegate** only; **block untitled windows**.
- **Panel close crashes** → `NSPanel.isReleasedWhenClosed = false` + convert close to **hide** (`orderOut(nil)`).
- **Focus flakiness** → Notification-driven `NSTextView` focus after a short delay once view is attached.
- **State not replacing** → `@ObservedObject ComposeModel` shared in controller; assign `model.text = incoming`.

---

## 6) Repro, Verification, and Troubleshooting

### 6.1 Build & Register
```bash
# Build Debug (shared derived data)
bash scripts/xc.sh Debug build

# Register only the intended bundle as the dev handler:
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -f -R ".derived/Build/Products/Debug/Contextify.app"

