# Current Work: Production Readiness & UX Polish

**Status:** Post-merge cleanup and production hardening
**Branch:** `feature/text-movement-refinements` (to be created)
**Last Updated:** 2025-10-04

---

## Overview

The `feature/python-daemon` branch has been successfully merged to `main`, bringing sub-30ms iTerm2 terminal capture via a long-running daemon. The daemon works perfectly with manually installed Python venv in `~/Library/Application Support/Contextify/`.

**Current state:**
- ✅ Daemon functional with <30ms E2E latency
- ✅ LaunchAgent lifecycle management
- ✅ Daemon script bundled in app Resources
- ❌ Python venv NOT bundled (must be manually installed)
- ❌ Swift daemon files not in Xcode project navigator
- ❌ Build script vs Xcode parity unverified

This document details the remaining **P0 blockers for production** and **P1 UX polish** items, along with validation strategies.

---

## P0: Production Blockers

### P0.1: Bundle Python Venv in App Resources

**Problem:**
The daemon requires a Python virtual environment with `iterm2==2.7` package. Currently, users must manually create this venv at `~/Library/Application Support/Contextify/venv/`. This is acceptable for development but blocks production release.

**Goal:**
Bundle a relocatable Python venv inside `Contextify.app/Contents/Resources/PythonVenv/` so the app works on fresh installs without manual setup.

#### Technical Approach

1. **Create relocatable venv:**
   ```bash
   # Clean slate
   rm -rf dist/PythonVenv

   # Create venv with system Python 3.13+
   python3 -m venv dist/PythonVenv

   # Upgrade pip (optional but recommended)
   dist/PythonVenv/bin/pip install --upgrade pip

   # Install iterm2 package
   dist/PythonVenv/bin/pip install 'iterm2==2.7'

   # Verify
   dist/PythonVenv/bin/python3 -c "import iterm2; print(iterm2.__version__)"
   ```

2. **Add to Xcode project:**
   - Open `Contextify.xcodeproj` in Xcode
   - Drag `dist/PythonVenv` into Project Navigator
   - **Critical:** Select "Create folder references" (blue folder icon, NOT yellow group)
   - Check "Copy items if needed" = NO (reference existing directory)
   - Target membership: Check "Contextify"
   - Build Phases → Copy Bundle Resources: Verify `PythonVenv` appears

3. **Verify bundled:**
   ```bash
   # Build via script
   bash scripts/xc.sh build

   # Check venv exists
   ls -la .derived/Build/Products/Debug/Contextify.app/Contents/Resources/PythonVenv/

   # Check Python executable
   .derived/Build/Products/Debug/Contextify.app/Contents/Resources/PythonVenv/bin/python3 --version

   # Check iterm2 package
   .derived/Build/Products/Debug/Contextify.app/Contents/Resources/PythonVenv/bin/python3 -c "import iterm2; print(iterm2.__version__)"
   ```

4. **Update LaunchAgentManager.swift:**
   - Already handles bundled venv (looks for `Bundle.main.url(forResource: "PythonVenv", withExtension: nil)`)
   - Falls back to existing venv for dev workflow
   - No code changes needed if venv named exactly "PythonVenv"

#### Validation

**Automated validation script:**
```bash
#!/bin/bash
# scripts/validate-bundled-resources.sh

set -e

APP_PATH="${1:-.derived/Build/Products/Debug/Contextify.app}"
RESOURCES="$APP_PATH/Contents/Resources"

echo "🔍 Validating bundled resources in: $APP_PATH"

# Check daemon script
if [[ ! -f "$RESOURCES/iterm2_daemon.py" ]]; then
    echo "❌ FAIL: iterm2_daemon.py not bundled"
    exit 1
fi
echo "✅ iterm2_daemon.py bundled ($(stat -f%z "$RESOURCES/iterm2_daemon.py") bytes)"

# Check venv directory
if [[ ! -d "$RESOURCES/PythonVenv" ]]; then
    echo "❌ FAIL: PythonVenv directory not bundled"
    exit 1
fi
echo "✅ PythonVenv directory bundled"

# Check Python binary
PYTHON="$RESOURCES/PythonVenv/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
    echo "❌ FAIL: Python binary not executable at $PYTHON"
    exit 1
fi
PYVER=$("$PYTHON" --version 2>&1)
echo "✅ Python executable: $PYVER"

# Check iterm2 package
if ! "$PYTHON" -c "import iterm2" 2>/dev/null; then
    echo "❌ FAIL: iterm2 package not installed in bundled venv"
    exit 1
fi
ITERM2_VER=$("$PYTHON" -c "import iterm2; print(iterm2.__version__)")
echo "✅ iterm2 package: v$ITERM2_VER"

# Check legacy reader (should still be bundled)
if [[ ! -f "$RESOURCES/iterm2_reader.py" ]]; then
    echo "⚠️  WARN: iterm2_reader.py not bundled (legacy fallback)"
fi

echo ""
echo "🎉 All bundled resources validated successfully!"
```

**Manual validation (human-in-loop):**
1. **Clean install test:**
   ```bash
   # Remove manual venv
   rm -rf ~/Library/Application\ Support/Contextify/venv

   # Stop daemon
   launchctl bootout gui/$(id -u)/dev.contextify.iterm2-daemon 2>/dev/null || true

   # Remove LaunchAgent
   rm -f ~/Library/LaunchAgents/dev.contextify.iterm2-daemon.plist

   # Build and launch
   bash scripts/xc.sh build
   open .derived/Build/Products/Debug/Contextify.app

   # Wait 3s, press Cmd+Shift+K+K in iTerm2
   # Expected: Text captured successfully (no error about missing venv)

   # Verify daemon running with bundled venv
   bash scripts/healthcheck.sh
   cat ~/Library/LaunchAgents/dev.contextify.iterm2-daemon.plist | grep ProgramArguments -A 5
   # Should show path to bundled venv, NOT ~/Library/Application Support/
   ```

2. **Archive build test:**
   ```bash
   # Clean build folder
   rm -rf .derived

   # Archive build (requires proper code signing)
   xcodebuild -project Contextify/Contextify.xcodeproj \
     -scheme Contextify \
     -configuration Release \
     -archivePath .derived/Contextify.xcarchive \
     archive

   # Export app
   xcodebuild -exportArchive \
     -archivePath .derived/Contextify.xcarchive \
     -exportPath .derived/export \
     -exportOptionsPlist scripts/ExportOptions.plist  # Create if needed

   # Validate bundled resources
   bash scripts/validate-bundled-resources.sh .derived/export/Contextify.app
   ```

**Acceptance criteria:**
- [ ] `bash scripts/validate-bundled-resources.sh` passes for Debug build
- [ ] `bash scripts/validate-bundled-resources.sh` passes for Release build
- [ ] Clean install (no manual venv) works on first hotkey press
- [ ] LaunchAgent plist references bundled venv path (not ~/Library/Application Support/)
- [ ] Daemon healthcheck passes: `bash scripts/healthcheck.sh`
- [ ] Latency <30ms P95: `tail -100 ~/Library/Application\ Support/Contextify/logs/daemon.stderr.log | grep latency_ms`

---

### P0.2: Verify Build Script ↔️ Xcode Parity

**Problem:**
We have two build methods:
1. Command-line: `bash scripts/xc.sh build`
2. Xcode GUI: Product → Run (or Cmd+R)

It's unclear if they produce identical builds, particularly regarding bundled resources. Differences could cause "works in Xcode, fails from script" bugs (or vice versa).

**Goal:**
Verify both methods produce byte-for-byte identical builds (excluding timestamps and signatures).

#### Technical Approach

1. **Align build settings:**
   - Both methods already use `.derived` as DerivedDataPath
   - Both target `Debug` configuration by default
   - Xcode GUI adds extra flags: `-NSDocumentRevisionsDebugMode YES`
   - These flags should NOT affect resource bundling

2. **Create comparison script:**
   ```bash
   #!/bin/bash
   # scripts/compare-builds.sh

   set -e

   echo "🧹 Cleaning build artifacts..."
   rm -rf .derived

   echo "🔨 Building via script..."
   bash scripts/xc.sh build

   # Capture resources list
   find .derived/Build/Products/Debug/Contextify.app/Contents/Resources \
     -type f \
     | sort > /tmp/script-build-resources.txt

   # Capture file hashes (exclude .plist which may have timestamps)
   find .derived/Build/Products/Debug/Contextify.app/Contents/Resources \
     -type f \
     ! -name "*.plist" \
     -exec shasum -a 256 {} \; \
     | sort > /tmp/script-build-hashes.txt

   echo "🧹 Cleaning for Xcode build..."
   rm -rf .derived

   echo "⚠️  MANUAL STEP: Open Xcode and run Product → Clean Build Folder"
   echo "⚠️  Then run Product → Run (Cmd+R)"
   echo "⚠️  Press Enter when build is complete..."
   read -r

   # Capture resources list
   find .derived/Build/Products/Debug/Contextify.app/Contents/Resources \
     -type f \
     | sort > /tmp/xcode-build-resources.txt

   # Capture file hashes
   find .derived/Build/Products/Debug/Contextify.app/Contents/Resources \
     -type f \
     ! -name "*.plist" \
     -exec shasum -a 256 {} \; \
     | sort > /tmp/xcode-build-hashes.txt

   echo ""
   echo "📊 Comparing resource lists..."
   if diff /tmp/script-build-resources.txt /tmp/xcode-build-resources.txt; then
       echo "✅ Resource lists identical"
   else
       echo "❌ Resource lists differ!"
       echo "Files only in script build:"
       comm -23 /tmp/script-build-resources.txt /tmp/xcode-build-resources.txt
       echo "Files only in Xcode build:"
       comm -13 /tmp/script-build-resources.txt /tmp/xcode-build-resources.txt
       exit 1
   fi

   echo ""
   echo "📊 Comparing resource hashes..."
   if diff /tmp/xcode-build-hashes.txt /tmp/script-build-hashes.txt; then
       echo "✅ Resource hashes identical"
   else
       echo "❌ Resource hashes differ!"
       diff /tmp/script-build-hashes.txt /tmp/xcode-build-hashes.txt || true
       exit 1
   fi

   echo ""
   echo "🎉 Build parity verified! Script and Xcode produce identical resources."
   ```

#### Validation

**Automated validation:**
```bash
# Run comparison script
bash scripts/compare-builds.sh
```

**Manual validation (human-in-loop):**

1. **Visual inspection:**
   ```bash
   # After both builds complete
   ls -lR .derived/Build/Products/Debug/Contextify.app/Contents/Resources/

   # Check for PythonVenv
   ls -la .derived/Build/Products/Debug/Contextify.app/Contents/Resources/PythonVenv/bin/

   # Check for daemon script
   ls -lh .derived/Build/Products/Debug/Contextify.app/Contents/Resources/iterm2_daemon.py
   ```

2. **Functional test both builds:**
   ```bash
   # Test script build
   bash scripts/xc.sh build
   open .derived/Build/Products/Debug/Contextify.app
   # Press Cmd+Shift+K+K, verify fast capture

   # Kill app
   killall Contextify

   # Test Xcode build
   # In Xcode: Product → Run
   # Press Cmd+Shift+K+K, verify fast capture
   ```

**Acceptance criteria:**
- [ ] `bash scripts/compare-builds.sh` completes successfully
- [ ] No differences in bundled resource files (same count, same paths)
- [ ] No differences in resource file hashes (excluding .plist timestamps)
- [ ] Both builds pass `bash scripts/validate-bundled-resources.sh`
- [ ] Both builds achieve <30ms latency in manual hotkey test
- [ ] Document any intentional differences (if found)

---

### P0.3: Add Swift Files to Xcode Project Navigator

**Problem:**
`LaunchAgentManager.swift` and `ITerm2DaemonClient.swift` are tracked in git and compile successfully, but they're not visible in Xcode's Project Navigator. Swift allows compiling files outside the project structure, but this causes issues:

- Files won't be included in Archive/Release builds
- Can't edit files in Xcode GUI (hard to discover for new contributors)
- Refactoring tools won't see these files
- Code navigation (Cmd+Click) may fail

**Goal:**
Add both Swift files to Xcode project with proper target membership so they appear in Project Navigator and work in all build configurations.

#### Technical Approach

1. **Verify files exist:**
   ```bash
   ls -l Contextify/Contextify/LaunchAgentManager.swift
   ls -l Contextify/Contextify/ITerm2DaemonClient.swift
   ```

2. **Add to Xcode (manual - requires GUI):**
   - Open `Contextify/Contextify.xcodeproj` in Xcode
   - In Project Navigator, right-click on `Contextify` folder (yellow, under Contextify target)
   - Select "Add Files to 'Contextify'..."
   - Navigate to `Contextify/Contextify/` directory
   - Select:
     - `LaunchAgentManager.swift`
     - `ITerm2DaemonClient.swift`
   - **Important settings:**
     - ✅ "Copy items if needed" = NO (files already in correct location)
     - ✅ "Create groups" (NOT folder references)
     - ✅ "Add to targets" = Check "Contextify" only
   - Click "Add"

3. **Verify in project file:**
   ```bash
   # Files should appear in project.pbxproj
   grep -c "LaunchAgentManager.swift" Contextify/Contextify.xcodeproj/project.pbxproj
   # Should output: 2 (one PBXBuildFile, one PBXFileReference)

   grep -c "ITerm2DaemonClient.swift" Contextify/Contextify.xcodeproj/project.pbxproj
   # Should output: 2
   ```

4. **Clean build test:**
   ```bash
   # Clean all derived data
   rm -rf .derived

   # Build via script (uses project file)
   bash scripts/xc.sh build

   # Should succeed without warnings
   ```

#### Validation

**Automated validation:**
```bash
#!/bin/bash
# scripts/validate-xcode-project.sh

set -e

PROJ_FILE="Contextify/Contextify.xcodeproj/project.pbxproj"

echo "🔍 Validating Xcode project structure..."

# Check files in project.pbxproj
for FILE in "LaunchAgentManager.swift" "ITerm2DaemonClient.swift"; do
    COUNT=$(grep -c "$FILE" "$PROJ_FILE" || echo 0)
    if [[ $COUNT -lt 2 ]]; then
        echo "❌ FAIL: $FILE not properly added to Xcode project (found $COUNT references, need 2)"
        exit 1
    fi
    echo "✅ $FILE in Xcode project ($COUNT references)"
done

# Check files compile (they should be in a PBXSourcesBuildPhase)
if ! grep -A 200 "PBXSourcesBuildPhase" "$PROJ_FILE" | grep -q "LaunchAgentManager.swift"; then
    echo "❌ FAIL: LaunchAgentManager.swift not in Sources build phase"
    exit 1
fi
echo "✅ LaunchAgentManager.swift in Sources build phase"

if ! grep -A 200 "PBXSourcesBuildPhase" "$PROJ_FILE" | grep -q "ITerm2DaemonClient.swift"; then
    echo "❌ FAIL: ITerm2DaemonClient.swift not in Sources build phase"
    exit 1
fi
echo "✅ ITerm2DaemonClient.swift in Sources build phase"

echo ""
echo "🎉 Xcode project structure validated!"
```

**Manual validation (human-in-loop):**

1. **Visual check in Xcode:**
   - Open `Contextify.xcodeproj` in Xcode
   - Project Navigator should show:
     ```
     Contextify
       ├── Contextify (folder)
       │   ├── AppDelegate.swift
       │   ├── ContentView.swift
       │   ├── ITerm2DaemonClient.swift      ← Should be visible
       │   ├── LaunchAgentManager.swift      ← Should be visible
       │   ├── ...
     ```
   - Click on each file → should open in editor
   - Cmd+Click on class names → should navigate

2. **Build in Xcode GUI:**
   - Product → Clean Build Folder
   - Product → Build (Cmd+B)
   - Should succeed with no warnings about missing files

3. **Archive build:**
   ```bash
   # Try archive (requires valid signing)
   xcodebuild -project Contextify/Contextify.xcodeproj \
     -scheme Contextify \
     -configuration Release \
     -archivePath .derived/Contextify.xcarchive \
     archive

   # Should succeed without missing symbol errors
   ```

**Acceptance criteria:**
- [ ] Both files visible in Xcode Project Navigator
- [ ] `bash scripts/validate-xcode-project.sh` passes
- [ ] Files appear in Sources build phase (not just Copy Bundle Resources)
- [ ] Clean build succeeds: `bash scripts/xc.sh clean && bash scripts/xc.sh build`
- [ ] Archive build succeeds (or fails only on signing issues, not compilation)
- [ ] Cmd+Click navigation works in Xcode for both files
- [ ] No "missing file" warnings in Xcode

---

## P1: UX Polish

### P1.1: Fix Window Flashing on Text Capture

**Problem:**
When text is sent from the terminal to Contextify via Cmd+Shift+K+K, the Contextify window briefly disappears and then reappears. This creates a jarring flashing effect.

**Root cause:**
Aggressive window management code added to prevent duplicate compose windows. The code likely calls `window.close()` or `window.orderOut()` followed by re-creation, rather than reusing the existing window.

**Goal:**
Eliminate window flashing while still preventing duplicate windows. The window should remain stable and simply update its content when receiving text via URL scheme.

#### Technical Investigation

1. **Identify window lifecycle code:**
   ```bash
   # Find window management code
   grep -r "orderOut\|makeKeyAndOrderFront\|close()" Contextify/Contextify/*.swift

   # Check ComposePresenter
   cat Contextify/Contextify/ComposePresenter.swift

   # Check ComposeSheet
   cat Contextify/Contextify/ComposeSheet.swift

   # Check URL scheme handler
   grep -r "contextify-dev://compose" Contextify/Contextify/*.swift
   ```

2. **Expected behavior:**
   - URL scheme arrives: `contextify-dev://compose?text64=...`
   - ComposePresenter/Router checks: Does compose window exist?
     - If YES: Update existing window content, bring to front
     - If NO: Create new window with content
   - Window should NEVER close and reopen for content updates

3. **Likely culprits:**
   - `ComposePresenter.swift` or `ComposeURLRouter.swift` may be calling `dismiss()` then `present()`
   - Window may be getting deallocated and recreated
   - Multiple SwiftUI sheets or `.openWindow()` calls

#### Technical Approach

**Step 1: Add window state tracking:**
```swift
// In ComposePresenter or similar
@MainActor
class ComposeWindowManager: ObservableObject {
    static let shared = ComposeWindowManager()

    private var currentWindow: NSWindow?

    func showComposeWindow(text: String, title: String) {
        if let window = currentWindow, window.isVisible {
            // Window exists - just update content
            updateWindowContent(window: window, text: text, title: title)
            window.makeKeyAndOrderFront(nil)
        } else {
            // Create new window
            let window = createComposeWindow(text: text, title: title)
            currentWindow = window
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func updateWindowContent(window: NSWindow, text: String, title: String) {
        // Update window content without recreating
        // This requires exposing content update method on window's view
    }

    private func createComposeWindow(text: String, title: String) -> NSWindow {
        // Create window (existing code)
    }
}
```

**Step 2: Update URL router to use shared manager:**
```swift
// In ComposeURLRouter.swift
static func handle(_ url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "contextify-dev",
          components.host == "compose" else {
        return
    }

    let queryItems = components.queryItems ?? []
    let title = queryItems.first(where: { $0.name == "title" })?.value ?? "Compose"
    let text = decodeText(from: queryItems) ?? ""

    // Use shared manager instead of creating new window
    ComposeWindowManager.shared.showComposeWindow(text: text, title: title)
}
```

**Step 3: Remove aggressive window closing:**
- Search for and remove any `window.close()` or `window.orderOut()` calls in URL handling path
- Ensure window reuse logic runs BEFORE any window creation code

#### Validation

**Manual validation (human-in-loop required):**

1. **Before fix - reproduce issue:**
   ```bash
   # Launch app
   open .derived/Build/Products/Debug/Contextify.app

   # Open iTerm2, press Cmd+Shift+K+K
   # Observe: Window flashes (disappears/reappears)

   # Press Cmd+Shift+K+K again
   # Observe: Window flashes again
   ```

2. **After fix - verify stable:**
   ```bash
   # Rebuild with fix
   bash scripts/xc.sh build
   open .derived/Build/Products/Debug/Contextify.app

   # Press Cmd+Shift+K+K multiple times rapidly
   # Expected: Window content updates smoothly, NO flashing
   # Expected: Window stays in same screen position
   # Expected: Window focus remains stable
   ```

3. **Edge case testing:**
   ```bash
   # Test 1: Window closed manually
   # - Press Cmd+Shift+K+K (window opens)
   # - Close window manually (Cmd+W)
   # - Press Cmd+Shift+K+K again
   # Expected: Window reopens (no flash, first time is OK)

   # Test 2: Multiple rapid captures
   # - Press Cmd+Shift+K+K 10 times rapidly
   # Expected: Window updates each time, no flashing
   # Expected: No duplicate windows appear

   # Test 3: App backgrounded
   # - Hide app (Cmd+H)
   # - Press Cmd+Shift+K+K in iTerm2
   # Expected: App comes to foreground smoothly, no flash
   ```

**Acceptance criteria:**
- [ ] Window does not flash (disappear/reappear) on text capture
- [ ] Window content updates smoothly in place
- [ ] Window position remains stable across captures
- [ ] No duplicate windows appear (original requirement still met)
- [ ] Window reopens correctly if manually closed then triggered again
- [ ] Fast repeated captures (10 in 5 seconds) show no flashing

---

### P1.2: Text Replacement (vs Append) in Terminal

**Problem:**
When sending text from Contextify compose window back to the terminal, it currently **appends** to the existing terminal input. Users likely expect **replace** behavior (clear existing input, insert new text).

**Example current behavior:**
```
# Terminal shows:
$ echo "old text"

# User presses Cmd+Shift+K+K, edits in Contextify, sends back
# Terminal now shows:
$ echo "old text"echo "new text"  ← APPENDED, broken command
```

**Expected behavior:**
```
# Terminal shows:
$ echo "old text"

# User sends back from Contextify
# Terminal now shows:
$ echo "new text"  ← REPLACED
```

**Goal:**
Default to **replace mode**: Clear existing terminal input before inserting text from Contextify. Add recovery mechanism to undo accidental replacements.

#### Technical Approach

**Step 1: Implement replace mode in ITerm2Bridge:**

Current send logic (assumed):
```swift
// ITerm2Bridge.swift or similar
func sendTextToTerminal(_ text: String, mode: String) {
    // Current: Just sends keystrokes (appends)
    sendKeystrokes(text)
}
```

Updated replace logic:
```swift
func sendTextToTerminal(_ text: String, mode: String = "replace") {
    if mode == "replace" {
        // Clear existing input first
        clearCurrentInput()

        // Wait brief moment for clear to complete
        usleep(50_000) // 50ms

        // Send new text
        sendKeystrokes(text)
    } else {
        // Append mode (legacy)
        sendKeystrokes(text)
    }
}

private func clearCurrentInput() {
    // Option 1: Send Ctrl+U (clear line in bash/zsh)
    sendControlKey("u")

    // Option 2: Send Ctrl+A (move to start) + Ctrl+K (kill to end)
    // More reliable across shells
    sendControlKey("a")
    usleep(10_000)
    sendControlKey("k")
}

private func sendControlKey(_ key: String) {
    // Send control character via iTerm2 API or AppleScript
    let script = """
    tell application "iTerm2"
        tell current session of current window
            write text "\u{0001}" -- Ctrl+A
            -- or appropriate control code
        end tell
    end tell
    """
    // Execute AppleScript
}
```

**Step 2: Add text recovery cache:**
```swift
// TerminalContentReader.swift or new TerminalTextHistory.swift
@MainActor
class TerminalTextHistory {
    static let shared = TerminalTextHistory()

    private var history: [(text: String, timestamp: Date, source: String)] = []
    private let maxHistory = 20

    func saveBeforeReplace(_ text: String, source: String = "terminal") {
        history.insert((text, Date(), source), at: 0)
        if history.count > maxHistory {
            history.removeLast()
        }

        // Show brief toast
        showToast("Previous input saved to history (Cmd+Z available)")
    }

    func undoLastReplace() -> String? {
        guard !history.isEmpty else { return nil }
        let restored = history.removeFirst()
        return restored.text
    }

    func getHistory() -> [(text: String, timestamp: Date, source: String)] {
        return history
    }
}
```

**Step 3: Add undo mechanism:**
```swift
// Add to GlobalHotkeyManager or create new TerminalUndoManager
@MainActor
class TerminalUndoManager {
    static let shared = TerminalUndoManager()

    func registerUndoHotkey() {
        // Register Cmd+Z while iTerm2 is focused
        // On trigger: Restore last text from history
        // Implementation similar to existing Cmd+Shift+K+K hotkey
    }

    func performUndo() {
        guard let restoredText = TerminalTextHistory.shared.undoLastReplace() else {
            showToast("No recent replacements to undo")
            return
        }

        // Clear current input and restore
        ITerm2Bridge.shared.sendTextToTerminal(restoredText, mode: "replace")
        showToast("Restored previous input")
    }
}
```

**Step 4: Update send button logic:**
```swift
// In ComposeSheet.swift or similar
func sendButtonPressed() {
    let textToSend = composeText

    // Save current terminal input to history BEFORE replacing
    if let currentTerminalText = getCurrentTerminalInput() {
        TerminalTextHistory.shared.saveBeforeReplace(currentTerminalText)
    }

    // Send with replace mode
    ITerm2Bridge.shared.sendTextToTerminal(textToSend, mode: "replace")

    // Clear compose window
    if autoClearOnSend {
        composeText = ""
    }
}

private func getCurrentTerminalInput() -> String? {
    // Read current terminal input (same as Cmd+Shift+K+K capture)
    // This is the text that will be replaced
    return TerminalContentReader.shared.captureTerminalText()
}
```

#### Validation

**Manual validation (human-in-loop):**

1. **Basic replace test:**
   ```bash
   # In iTerm2, type:
   echo "original text"
   # Don't press Enter

   # Press Cmd+Shift+K+K
   # Edit in Contextify: "echo 'replacement text'"
   # Click Send

   # Expected in iTerm2:
   echo 'replacement text'  ← Original cleared, new text inserted
   # NOT: echo "original text"echo 'replacement text'
   ```

2. **Undo test:**
   ```bash
   # In iTerm2, type:
   ls -la /tmp

   # Press Cmd+Shift+K+K, edit to: pwd
   # Send from Contextify

   # Terminal now shows: pwd

   # Press Cmd+Z (undo hotkey)
   # Expected: ls -la /tmp  ← Restored

   # Press Cmd+Z again
   # Expected: "No recent replacements to undo" toast
   ```

3. **Empty line test:**
   ```bash
   # In iTerm2, empty prompt (nothing typed)

   # Press Cmd+Shift+K+K, type in Contextify: echo "test"
   # Send

   # Expected: echo "test"  ← Inserted on empty line
   # No errors from trying to clear empty line
   ```

4. **Multi-line test:**
   ```bash
   # In iTerm2, type multi-line command:
   for i in 1 2 3; do \
     echo $i
   # Don't complete it

   # Press Cmd+Shift+K+K, edit in Contextify
   # Send

   # Expected: Multi-line input cleared, new text inserted
   # May need special handling for multi-line (Ctrl+C first?)
   ```

5. **History persistence test:**
   ```bash
   # Replace text 5 times rapidly
   # Press Cmd+Z repeatedly
   # Expected: Can undo all 5 replacements in reverse order
   # Expected: History limited to 20 items (oldest evicted)
   ```

**Acceptance criteria:**
- [ ] Sending text **replaces** terminal input (not appends)
- [ ] Empty terminal line handled gracefully (no errors)
- [ ] Multi-line input cleared correctly (may need Ctrl+C escape hatch)
- [ ] Previous input saved to history automatically before replace
- [ ] Cmd+Z undo restores last replaced text
- [ ] Can undo up to 20 recent replacements
- [ ] Toast notifications confirm history save and undo actions
- [ ] Undo only works when iTerm2 is focused (same as capture hotkey)
- [ ] Add preference toggle for replace vs append mode (future)

**Advanced (optional):**
- [ ] Add mode selector in Compose UI: [ Replace | Append ]
- [ ] Remember user's mode preference in UserDefaults
- [ ] Add Cmd+Shift+Return shortcut for "send without replace"
- [ ] Show history panel (Cmd+H?) listing recent replacements with timestamps

---

## Implementation Plan

### Recommended Branch Strategy

Create a new feature branch for all P0 and P1 work:

```bash
# Ensure main is up to date
git checkout main
git pull origin main  # If working with remote

# Create feature branch
git checkout -b feature/text-movement-refinements

# Work on P0.1 - P0.3, commit atomically
git add ...
git commit -m "feat(build): bundle Python venv in app Resources"

git add ...
git commit -m "test(build): add validation scripts for build parity"

git add ...
git commit -m "fix(xcode): add daemon Swift files to project navigator"

# Work on P1.1 - P1.2, commit atomically
git add ...
git commit -m "fix(ux): eliminate window flashing on text capture"

git add ...
git commit -m "feat(terminal): implement text replacement with undo history"

# Merge back to main when all complete
git checkout main
git merge --no-ff feature/text-movement-refinements
```

### Suggested Work Order

**Session 1: P0 Blockers (Production)**
1. **P0.1: Bundle venv** (30-45 min)
   - Create venv, add to Xcode, validate
   - Highest priority for production readiness

2. **P0.3: Add Swift files** (10 min)
   - Quick Xcode GUI task, enables better development

3. **P0.2: Verify build parity** (20 min)
   - Run comparison script, document results
   - May surface issues from P0.1/P0.3

**Session 2: P1 Polish (UX)**
4. **P1.1: Fix window flashing** (30-60 min)
   - Investigate window lifecycle, implement reuse
   - Manual testing required

5. **P1.2: Text replacement** (60-90 min)
   - Most complex: Replace logic, history, undo hotkey
   - Extensive manual testing needed

### Testing Checklist

Before merging `feature/text-movement-refinements` → `main`:

**P0 Validation:**
- [ ] `bash scripts/validate-bundled-resources.sh` passes
- [ ] `bash scripts/compare-builds.sh` passes
- [ ] `bash scripts/validate-xcode-project.sh` passes
- [ ] Clean install works (no manual venv setup)
- [ ] Archive build succeeds (or only fails on signing)

**P1 Validation:**
- [ ] No window flashing on 10 rapid captures
- [ ] Text replacement works (clears then inserts)
- [ ] Undo (Cmd+Z) restores previous terminal input
- [ ] History persists up to 20 items

**Integration:**
- [ ] Daemon still achieves <30ms latency after changes
- [ ] `bash scripts/healthcheck.sh` passes
- [ ] All Swift files compile with zero warnings
- [ ] No regressions in existing functionality

---

## Success Metrics

**P0 Completion = Production Ready:**
- App can be built, archived, and distributed without manual setup
- Fresh install on new Mac works immediately
- Consistent builds across all methods (script, Xcode, CI)

**P1 Completion = Polished UX:**
- Smooth, flicker-free window updates
- Intuitive text replacement with safety net (undo)
- Professional feel matching quality of <30ms daemon performance

**Timeline Estimate:**
- P0 work: 1-2 hours (mostly automated validation)
- P1 work: 2-3 hours (manual testing, iteration on UX)
- Total: Half-day to full-day development session

---

**Next Steps:**
1. Create `feature/text-movement-refinements` branch
2. Start with P0.1 (bundle venv) - highest impact
3. Validate each P0 item before moving to P1
4. Iterate on P1 UX based on manual testing feedback
5. Merge to main when all acceptance criteria met

**Questions/Blockers:**
- Code signing certificates available for Archive builds?
- Preferences for undo hotkey (Cmd+Z may conflict with shell)?
- Should append mode be preserved as option, or replace-only?

---

**Last Updated:** 2025-10-04
**Owner:** Development team
**Status:** Ready to implement
