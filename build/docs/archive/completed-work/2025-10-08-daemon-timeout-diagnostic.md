# iTerm2 Daemon Timeout Diagnostic Report

**Date:** 2025-10-08
**Issue:** Global hotkey (Cmd+Shift+K+K) failing with daemon timeout error
**Severity:** P0 - Blocks core functionality
**Status:** Root cause identified, mitigation strategies provided

---

## Executive Summary

The "server_timeout (content fetch exceeded 450ms)" error is **NOT** caused by missing Python bundling as initially suspected. The root cause is a **combination of broken venv structure and iTerm2 websocket connection failures**. The bundled PythonVenv uses symlinks to system Python, which breaks when copied to Application Support. Additionally, the daemon cannot establish websocket connections to iTerm2, failing with "no close frame received or sent" errors.

**Impact on Release Readiness:**
- Current assumptions in `build/notes/release-readiness.md` lines 82-100 are **partially incorrect**
- Python resources ARE bundled, but in a broken state (symlinked, not standalone)
- Venv auto-repair and health checking logic needs to be implemented before DMG release

---

## Root Cause Analysis

### Problem Chain

1. **Bundled PythonVenv Structure Issue**
   ```bash
   # Bundled venv uses symlinks (breaks on copy)
   .derived/Build/Products/Debug/Contextify.app/Contents/Resources/PythonVenv/bin/python3
   -> /Applications/Xcode.app/Contents/Developer/usr/bin/python3
   ```
   - LaunchAgentManager copies this venv to `~/Library/Application Support/Contextify/venv/`
   - Symlink is preserved during copy
   - Daemon uses system Python, not bundled site-packages
   - This defeats the purpose of bundling

2. **User Workaround (Currently Active)**
   ```bash
   ~/Library/Application Support/Contextify/venv/
   ├── bin/python3 -> python3.13  # User manually created python3.13 venv
   └── lib/python3.13/site-packages/iterm2/  # Has iterm2 2.7
   ```
   - User manually created python3.13 venv with iterm2 2.7
   - This works but creates version mismatch with LaunchAgent plist:
     - Plist expects: `/Users/rob/Library/Application Support/Contextify/venv/bin/python3` (should be 3.9)
     - Actual: python3.13

3. **iTerm2 Websocket Connection Failures**
   ```json
   // From daemon.stderr.log (last 100 entries)
   {"level": "WARN", "event": "iterm2_connect_failed", "attempt": 1,
    "delay_s": 1, "err": "no close frame received or sent"}
   {"level": "ERROR", "event": "health_probe_reconnect_failed"}
   ```
   - Daemon IS running successfully
   - iterm2 module IS imported correctly (2.7)
   - But websocket handshake with iTerm2 fails
   - Connection attempts timeout after 3 retries
   - This is why the 450ms timeout in `fetch_content()` is exceeded

### What Works ✅

- ✅ Bundled resources exist in app bundle:
  - `.derived/.../Resources/Python/lib/python/site-packages/iterm2` (bundled dependencies)
  - `.derived/.../Resources/PythonVenv/` (venv template, but broken)
  - `.derived/.../Resources/iterm2_daemon.py` (daemon script)

- ✅ LaunchAgent is installed and running:
  ```bash
  ~/Library/LaunchAgents/dev.contextify.iterm2-daemon.plist
  ```

- ✅ Daemon script is copied correctly:
  ```bash
  ~/Library/Application Support/Contextify/scripts/iterm2_daemon.py
  ```

- ✅ iterm2 2.7 is installed in user's manual venv:
  ```bash
  $ ~/Library/Application\ Support/Contextify/venv/bin/python3 -c "import iterm2; print(iterm2.__version__)"
  2.7
  ```

### What's Broken ❌

- ❌ Bundled PythonVenv uses symlinks instead of standalone Python:
  ```bash
  $ ls -la .derived/.../PythonVenv/bin/python3
  lrwxr-xr-x -> /Applications/Xcode.app/Contents/Developer/usr/bin/python3
  ```

- ❌ LaunchAgentManager.swift doesn't validate venv health before use

- ❌ No auto-repair logic when venv is broken

- ❌ Daemon cannot connect to iTerm2 via websocket:
  - Error: "no close frame received or sent"
  - Suggests iTerm2 Python API not enabled OR version incompatibility

- ❌ User error message is misleading:
  - Says "Python environment is not bundled in the app"
  - Actually, it IS bundled, but in a broken state

---

## Diagnostic Steps Performed

### 1. Log Analysis
```bash
# Daemon error logs (975KB of repeated connection failures)
$ ls -lh ~/Library/Application\ Support/Contextify/logs/
-rw-------  998087 Oct  8 16:13 daemon.stderr.log

# Pattern: Continuous reconnection attempts
$ tail -100 daemon.stderr.log | jq -r .event | sort | uniq -c
     33 iterm2_connect_failed
     11 health_probe_reconnecting
     11 health_probe_reconnect_failed
```

### 2. Venv Structure Analysis
```bash
# User's working venv (manual fix)
$ ~/Library/Application\ Support/Contextify/venv/bin/python3 --version
3.13.5

$ ~/Library/Application\ Support/Contextify/venv/bin/python3 -c "import sys; print(sys.path)"
[
  '/opt/homebrew/lib/python3.13/site-packages',  # System packages
  '/Users/rob/Library/Application Support/Contextify/venv/lib/python3.13/site-packages'  # User venv
]

# Bundled venv (broken - symlinked)
$ ls -la .derived/.../PythonVenv/bin/
lrwxr-xr-x python3 -> /Applications/Xcode.app/Contents/Developer/usr/bin/python3
```

### 3. Code Flow Analysis
```swift
// LaunchAgentManager.swift:68-86
if fm.isExecutableFile(atPath: pythonBin.path) {
    log.info("Using existing valid venv at \(self.venvDir.path)")
} else {
    // Try to copy from bundle
    guard let venvSrc = Bundle.main.url(forResource: "PythonVenv", withExtension: nil) else {
        throw NSError(...)  // Error: bundled PythonVenv missing
    }
    // ... copies broken symlinked venv
}
```

**Issue:** The check `fm.isExecutableFile(atPath: pythonBin.path)` passes for symlinked Python, so broken venv is considered "valid"

### 4. Daemon Connection Test
```bash
# Daemon socket exists
$ ls -la ~/Library/Application\ Support/Contextify/run/
-rw------- daemon.path  # Contains socket path

# LaunchAgent is loaded
$ launchctl print gui/$(id -u)/dev.contextify.iterm2-daemon
(shows service is running, PID active)

# But connection fails at iTerm2 websocket level
# iterm2_daemon.py:171-186 connect_iterm() always fails
```

### 5. Bundle Resource Verification
```bash
# Both Python packaging approaches exist in bundle
$ ls -la .derived/.../Resources/
drwxr-xr-x  Python/          # Direct site-packages (from bundle_python.sh)
drwxr-xr-x  PythonVenv/      # Venv template (broken)
-rwxr-xr-x  iterm2_daemon.py

# Python/ has correct packages
$ ls Python/lib/python/site-packages/
iterm2-2.10.dist-info/  # Note: 2.10, not 2.7!
websockets/
google/

# PythonVenv/ has 2.7
$ ls PythonVenv/lib/python3.9/site-packages/
iterm2-2.7.dist-info/
```

**VERSION MISMATCH FOUND:**
- `Resources/Python/` has iterm2 2.10
- `Resources/PythonVenv/` has iterm2 2.7
- User's manual venv has iterm2 2.7
- iterm2_daemon.py lines 31-45 checks for venv/lib/python3/site-packages first, falls back to dev paths

---

## Why the Current Error Message is Misleading

**Current alert (TerminalContentReader.swift:142-155):**
```
"The fast iTerm2 daemon failed to start: daemon error: server_timeout (content fetch exceeded 450ms)

This is likely because the Python environment is not bundled in the app."
```

**Reality:**
- Python environment IS bundled (both `Python/` and `PythonVenv/`)
- Daemon IS running (not a startup failure)
- The timeout is in `fetch_content()`, not daemon startup
- Real issue: Daemon can't connect to iTerm2 websocket API

**Better error message:**
```
"iTerm2 integration failed: Daemon cannot connect to iTerm2

This could mean:
• iTerm2 Python API is disabled (check iTerm2 → Preferences → General → Magic)
• iTerm2 version incompatibility
• Python environment needs to be rebuilt

Would you like Contextify to attempt auto-repair?"
```

---

## Auto-Repair Strategy

### Health Check Logic

```swift
// LaunchAgentManager.swift - Add this validation
enum VenvStatus {
    case healthy
    case missing
    case symlinkToSystem  // BROKEN - needs rebuild
    case missingDependencies
    case versionMismatch
}

func validateVenv() async -> VenvStatus {
    let pythonBin = venvDir.appendingPathComponent("bin/python3")

    // Check 1: Executable exists
    guard FileManager.default.isExecutableFile(atPath: pythonBin.path) else {
        return .missing
    }

    // Check 2: Not a symlink to system Python (CRITICAL CHECK - currently missing)
    do {
        let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: pythonBin.path)
        if resolved.contains("/usr/bin") ||
           resolved.contains("Xcode.app") ||
           resolved.contains("/opt/homebrew") {
            log.warning("Venv python is symlinked to system: \(resolved)")
            return .symlinkToSystem  // BROKEN - will fail when app bundle moves
        }
    } catch {
        // Not a symlink - good (or unreadable)
    }

    // Check 3: Can import iterm2 with correct version
    let testCmd = "\(pythonBin.path) -c 'import iterm2; print(iterm2.__version__)'"
    guard let (exitCode, output) = try? run("/bin/sh", ["-c", testCmd]),
          exitCode == 0 else {
        return .missingDependencies
    }

    // Check 4: Version matches expectation
    let expectedVersion = "2.7"  // or read from config
    if !output.contains(expectedVersion) {
        log.warning("iterm2 version mismatch: got \(output), expected \(expectedVersion)")
        return .versionMismatch
    }

    return .healthy
}
```

### Repair Strategies (Priority Order)

#### **Strategy 1: Rebuild from System Python** ⭐ RECOMMENDED
```swift
func rebuildVenvFromSystem() async throws {
    log.info("Rebuilding venv from system Python")

    // Clean slate
    if FileManager.default.fileExists(atPath: venvDir.path) {
        try FileManager.default.removeItem(at: venvDir)
    }

    // Create fresh venv with --copies to avoid symlinks
    let (exit1, output1) = try run("/usr/bin/python3", [
        "-m", "venv",
        "--copies",  // CRITICAL: Avoid symlinks
        venvDir.path
    ])
    guard exit1 == 0 else {
        throw NSError(domain: "Contextify", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "venv creation failed: \(output1)"])
    }

    // Install iterm2
    let pip = venvDir.appendingPathComponent("bin/pip3")
    let (exit2, output2) = try run(pip.path, [
        "install",
        "--no-cache-dir",  // Fresh download
        "iterm2==2.7"      // Pin version
    ])
    guard exit2 == 0 else {
        throw NSError(domain: "Contextify", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "pip install failed: \(output2)"])
    }

    log.info("Venv rebuild complete")
}
```

**Pros:**
- Works on any Mac with system Python
- No bundling complexity
- Always gets fresh packages

**Cons:**
- Requires internet connection
- ~30 second setup time on first run
- Depends on system Python being available

#### **Strategy 2: Use Bundled Python Directory** (Fallback)
```swift
func useBundledPythonSitePackages() async throws {
    // Modify LaunchAgent plist to use bundled Python directly
    let bundlePython = Bundle.main.resourceURL!
        .appendingPathComponent("Python/lib/python/site-packages")

    // Update daemon to use this path
    // Modify iterm2_daemon.py startup to:
    // sys.path.insert(0, bundlePython.path)

    // Problem: Need a Python interpreter still
    // This only works if we have standalone Python bundled
}
```

#### **Strategy 3: Bundle Standalone Python** (Future - Best UX)
```swift
// Use python-build-standalone from https://github.com/indygreg/python-build-standalone
// Bundle complete Python 3.11 (~20MB)
// Create venv from bundled Python
// No internet required, instant setup
```

### User-Facing Flow

```swift
// In LaunchAgentManager.installIfNeeded()
func installIfNeeded() async throws {
    try createDirs()
    rotateLogsIfNeeded()

    // Copy daemon script (always)
    try copyDaemonScript()

    // Check venv health
    let status = await validateVenv()

    switch status {
    case .healthy:
        log.info("Venv is healthy, using existing")

    case .missing, .symlinkToSystem, .missingDependencies, .versionMismatch:
        // Show user-friendly setup dialog
        await showSetupDialog(reason: status)

        // Rebuild venv
        try await rebuildVenvFromSystem()
    }

    try writePlist()
    try bootstrapAndEnable()
}

@MainActor
func showSetupDialog(reason: VenvStatus) async {
    let alert = NSAlert()
    alert.messageText = "iTerm2 Integration Setup"

    let reason_text = switch reason {
    case .missing: "first-time setup"
    case .symlinkToSystem: "the bundled Python environment is broken"
    case .missingDependencies: "required packages are missing"
    case .versionMismatch: "package versions need updating"
    default: "setup is required"
    }

    alert.informativeText = """
    Contextify needs to configure iTerm2 integration (\(reason_text)).

    This will:
    • Create a Python environment (~50MB)
    • Install iTerm2 Python API (v2.7)
    • Configure background service

    Time: ~30 seconds
    Requires: Internet connection
    """

    alert.addButton(withTitle: "Set Up Now")
    alert.addButton(withTitle: "Skip (hotkey won't work)")

    if alert.runModal() == .alertSecondButtonReturn {
        throw NSError(domain: "Contextify", code: 99,
                      userInfo: [NSLocalizedDescriptionKey: "User declined venv setup"])
    }
}
```

### Progress Feedback

```swift
// Add progress reporting to LaunchAgentManager
actor ProgressReporter {
    var currentStatus: String = ""
    var observers: [(String) -> Void] = []

    func update(_ status: String) {
        currentStatus = status
        observers.forEach { $0(status) }
    }
}

// In rebuildVenvFromSystem()
func rebuildVenvFromSystem(progress: ProgressReporter) async throws {
    await progress.update("Creating Python environment...")
    try run("/usr/bin/python3", ["-m", "venv", "--copies", venvDir.path])

    await progress.update("Downloading iTerm2 API...")
    let pip = venvDir.appendingPathComponent("bin/pip3")
    try run(pip.path, ["install", "iterm2==2.7"])

    await progress.update("Verifying installation...")
    let status = await validateVenv()
    guard status == .healthy else {
        throw NSError(...)
    }

    await progress.update("✅ Setup complete!")
}
```

---

## Daemon Connection Issue (Secondary Problem)

Even with a healthy venv, the daemon fails to connect to iTerm2. This is a separate issue.

### Potential Causes

1. **iTerm2 Python API Not Enabled**
   ```
   iTerm2 → Preferences → General → Magic
   ☐ Enable Python API  ← Must be checked
   ```

2. **iTerm2 Version Incompatibility**
   - iterm2 2.7 released: 2020-05-23
   - May not work with latest iTerm2 builds
   - Consider upgrading to iterm2 2.10 (bundled in `Resources/Python/`)

3. **Websocket Permission Issue**
   - macOS firewall blocking local websocket?
   - Localhost connection blocked by network settings?

4. **iTerm2 Not Running**
   - Daemon attempts to connect before iTerm2 launches
   - No retry logic for "iTerm2 not available yet"

### Diagnostic Steps for User

```bash
# 1. Check iTerm2 Python API status
# iTerm2 → Preferences → General → Magic → Enable Python API

# 2. Test websocket connection manually
python3 -c "
import asyncio
import iterm2

async def test():
    conn = await iterm2.Connection.async_create()
    app = await iterm2.async_get_app(conn)
    print(f'Connected! Version: {await app.async_get_app_version()}')

asyncio.run(test())
"

# 3. Check iTerm2 version
# iTerm2 → About iTerm2
# Should be 3.x or later

# 4. Try iterm2 2.10 instead
pip install --upgrade iterm2==2.10
launchctl kickstart gui/$(id -u)/dev.contextify.iterm2-daemon
```

### Daemon Improvements Needed

```python
# iterm2_daemon.py:171-186 - Add better error handling
async def connect_iterm(self) -> bool:
    for attempt in range(3):
        try:
            self.iterm_conn = await iterm2.Connection.async_create()
            self.iterm_app = await iterm2.async_get_app(self.iterm_conn)

            # NEW: Verify connection works
            try:
                version = await asyncio.wait_for(
                    self.iterm_app.async_get_app_version(),
                    timeout=2.0
                )
                slog("INFO", "iterm2_connected", attempt=attempt + 1, version=version)
                self.conn_healthy = True
                self.metrics["iterm2_down"] = False
                return True
            except asyncio.TimeoutError:
                slog("WARN", "iterm2_connect_timeout", attempt=attempt + 1)
                # Connection made but API not responding
                await self.iterm_conn.close()

        except Exception as e:
            # Better error categorization
            err_str = str(e)
            if "no close frame" in err_str:
                slog("WARN", "iterm2_websocket_handshake_failed",
                     attempt=attempt + 1, err=err_str,
                     hint="Check iTerm2 → Preferences → General → Magic → Enable Python API")
            elif "Connection refused" in err_str:
                slog("WARN", "iterm2_not_running", attempt=attempt + 1)
            else:
                slog("WARN", "iterm2_connect_failed", attempt=attempt + 1, err=err_str)

            delay = 2 ** attempt
            await asyncio.sleep(delay)

    self.conn_healthy = False
    self.metrics["iterm2_down"] = True
    slog("ERROR", "iterm2_unavailable_after_retries",
         hint="Ensure iTerm2 is running and Python API is enabled")
    return False
```

---

## Release Readiness Impact

### Corrections to `build/notes/release-readiness.md`

#### **Section 1.1 (Lines 82-100) - Bundle Daemon Resources**

**Current (INCORRECT):**
```markdown
**Tasks:**
- [ ] Create release Python venv with iterm2==2.7 in `dist/PythonVenv`
- [ ] Add `scripts/iterm2_daemon.py` to Xcode Resources ✅ (Already done)
- [ ] Add `dist/PythonVenv` as folder reference to Xcode Resources
```

**Corrected:**
```markdown
**Tasks:**
- [x] ~~Create release Python venv~~ - SKIP: Venv will be built on first run
- [x] `scripts/iterm2_daemon.py` already in Xcode Resources
- [ ] REMOVE broken `PythonVenv` from bundle (causes confusion)
- [ ] ADD venv health check to LaunchAgentManager.validateVenv()
- [ ] ADD auto-repair logic (rebuild from system Python)
- [ ] ADD user-facing setup dialog with progress
- [ ] UPDATE error message to be accurate and actionable
```

**New Strategy:**
```markdown
#### 1.1.1 Venv Packaging Decision

**Selected: On-Demand Venv Creation** (matches FileKitty approach)

**Rationale:**
- Bundling standalone Python adds 20-25MB to app size
- Symlinked venvs break when app bundle moves (current issue)
- System Python (python3) is available on all macOS 12.3+ (our minimum: macOS 14)

**Implementation:**
- LaunchAgentManager checks venv health on launch
- If missing/broken: creates fresh venv from system Python
- Uses `python3 -m venv --copies` to avoid symlinks
- Installs iterm2==2.7 via pip
- Shows progress dialog during setup (~30s, one-time)

**First-Run Experience:**
1. User launches app
2. "iTerm2 Integration Setup" dialog appears
3. User clicks "Set Up Now"
4. Progress: "Creating Python environment..." → "Installing packages..." → "Done!"
5. Daemon starts automatically
6. Hotkey works

**Acceptance Criteria:**
- Fresh Mac: venv created automatically on first run
- Broken venv: auto-detected and repaired
- No internet: graceful failure with helpful error
- Progress shown to user (not silent 30s freeze)
```

#### **Section 1.3 (Lines 117-129) - Add Venv Validation**

**Add to Acceptance Criteria:**
```markdown
- [x] No differences in bundled resources between build methods
- [ ] **NEW:** Venv health check passes after clean install
- [ ] **NEW:** Auto-repair successfully rebuilds broken venv
- [ ] **NEW:** Setup dialog shows during first run (if venv needed)
- [ ] **NEW:** Daemon connects to iTerm2 after setup
```

#### **New Section: 1.4 - Daemon Connection Reliability**

```markdown
### Phase 1.4: Daemon-iTerm2 Connection Hardening
**Timeline:** 0.5 days
**Blocker:** No (degraded experience only)

**Issue:** Daemon fails to connect to iTerm2 with "no close frame received or sent"

**Tasks:**
- [ ] Improve daemon error logging with actionable hints
- [ ] Add iTerm2 version detection and compatibility check
- [ ] Consider upgrading to iterm2 2.10 (currently using 2.7 from 2020)
- [ ] Add "Check iTerm2 Settings" button to error dialog
- [ ] Document iTerm2 Python API setup in README

**Acceptance Criteria:**
- Daemon connection errors include specific remediation steps
- User can diagnose iTerm2 API issues without checking logs
- Fallback to AppleScript if daemon fails (already implemented)
```

### Updated P0 Checklist

```markdown
## P0 Blockers (MUST FIX before DMG release)

- [x] ~~Bundle Python venv~~ - NOT NEEDED, build on first run instead
- [ ] Implement venv health check (LaunchAgentManager.validateVenv)
- [ ] Implement venv auto-repair (rebuildVenvFromSystem)
- [ ] Add first-run setup dialog with progress
- [ ] Test clean install flow (fresh Mac simulation)
- [ ] Fix daemon connection issue OR document iTerm2 setup clearly
- [ ] Update error messages to be accurate and actionable
```

---

## Recommended Immediate Actions

### For User (Right Now)

**Step 1: Enable iTerm2 Python API**
```
iTerm2 → Preferences → General → Magic
✅ Enable Python API
```

**Step 2: Check for iTerm2 version compatibility**
```bash
# Check iTerm2 version
# iTerm2 → About iTerm2
# Should be Build 3.x or later

# Try upgrading iterm2 module to 2.10
~/Library/Application\ Support/Contextify/venv/bin/pip install --upgrade iterm2==2.10
launchctl kickstart gui/$(id -u)/dev.contextify.iterm2-daemon
```

**Step 3: Test daemon connection manually**
```bash
~/Library/Application\ Support/Contextify/venv/bin/python3 << 'EOF'
import asyncio
import iterm2

async def test():
    try:
        conn = await iterm2.Connection.async_create()
        app = await iterm2.async_get_app(conn)
        version = await app.async_get_app_version()
        print(f"✅ Connected to iTerm2 {version}")

        window = app.current_terminal_window
        if window:
            print(f"✅ Found active window")
        else:
            print("❌ No active window")

        await conn.close()
    except Exception as e:
        print(f"❌ Connection failed: {e}")

asyncio.run(test())
EOF
```

**Step 4: If still failing, rebuild venv completely**
```bash
# Nuclear option - fresh rebuild
rm -rf ~/Library/Application\ Support/Contextify/venv
python3 -m venv --copies ~/Library/Application\ Support/Contextify/venv
~/Library/Application\ Support/Contextify/venv/bin/pip install iterm2==2.7
launchctl kickstart gui/$(id -u)/dev.contextify.iterm2-daemon

# Wait 5 seconds, then check logs
sleep 5
tail -20 ~/Library/Application\ Support/Contextify/logs/daemon.stderr.log
```

### For Development (Priority Order)

**P0 - Required for Release:**

1. **Implement Venv Health Check** (2-3 hours)
   - File: `Contextify/Contextify/LaunchAgentManager.swift`
   - Add `validateVenv() -> VenvStatus` method
   - Check for symlinks to system Python
   - Verify iterm2 module version

2. **Implement Auto-Repair** (2-3 hours)
   - Add `rebuildVenvFromSystem()` method
   - Use `python3 -m venv --copies` to avoid symlinks
   - Show progress dialog during setup
   - Handle network failures gracefully

3. **Update Error Messages** (1 hour)
   - File: `Contextify/Contextify/TerminalContentReader.swift:142-155`
   - Replace misleading "Python environment is not bundled" message
   - Add actionable remediation steps
   - Link to iTerm2 settings

4. **Test Clean Install Flow** (1-2 hours)
   - Remove all app data: `rm -rf ~/Library/Application\ Support/Contextify`
   - Unload LaunchAgent: `launchctl bootout gui/$(id -u)/dev.contextify.iterm2-daemon`
   - Rebuild and test first-run experience
   - Verify venv created automatically

**P1 - Nice to Have:**

5. **Add Diagnostic Tool** (2-3 hours)
   - Menu item: "Debug → Daemon Diagnostics"
   - Generate report with venv status, logs, iTerm2 settings
   - Copy to clipboard or save to file

6. **Daemon Connection Improvements** (3-4 hours)
   - Better error categorization in daemon
   - Retry logic for "iTerm2 not running yet"
   - Consider iterm2 2.10 upgrade

**P2 - Post-Launch:**

7. **Bundle Standalone Python** (1-2 days)
   - Use python-build-standalone
   - Eliminates internet dependency
   - Instant setup, no waiting

8. **Fallback Mode** (3-4 hours)
   - Gracefully degrade to AppleScript-only mode
   - Show warning: "Fast mode unavailable, using legacy (slower)"

---

## Testing Checklist

### Venv Health Scenarios

- [ ] **Fresh Install (no venv)**
  - Expected: Auto-creates venv from system Python
  - Verify: Setup dialog shown, progress updates, daemon works

- [ ] **Broken Venv (symlinked)**
  - Setup: `python3 -m venv ~/Library/.../Contextify/venv` (creates symlinks)
  - Expected: Detected as broken, auto-repairs
  - Verify: Old venv deleted, new venv created with --copies

- [ ] **Missing iterm2 module**
  - Setup: Delete site-packages
  - Expected: Detected as broken, auto-repairs
  - Verify: iterm2 reinstalled

- [ ] **Wrong iterm2 version**
  - Setup: `pip install iterm2==1.0` (old version)
  - Expected: Detected as version mismatch, auto-repairs
  - Verify: Upgraded to 2.7

- [ ] **No Internet Connection**
  - Setup: Disable network
  - Expected: Graceful failure with helpful error
  - Verify: Error message: "Internet required to download iTerm2 API"

### Daemon Connection Scenarios

- [ ] **iTerm2 API Disabled**
  - Setup: Uncheck "Enable Python API" in iTerm2 prefs
  - Expected: Connection fails, error explains how to fix
  - Verify: Error message mentions iTerm2 preferences

- [ ] **iTerm2 Not Running**
  - Setup: Quit iTerm2
  - Expected: Daemon waits/retries, or shows clear error
  - Verify: Recovers when iTerm2 launches

- [ ] **iTerm2 Version Incompatibility**
  - Setup: Use very old or very new iTerm2
  - Expected: Version detected, compatibility noted
  - Verify: Error message mentions version issue

### End-to-End

- [ ] **Happy Path**
  1. Fresh Mac (simulated: delete all Contextify data)
  2. Launch app
  3. Setup dialog appears
  4. User clicks "Set Up Now"
  5. Progress shown (~30s)
  6. Daemon starts
  7. Press Cmd+Shift+K+K
  8. Terminal content captured ✅

- [ ] **Recovery Path**
  1. Existing broken venv
  2. Press Cmd+Shift+K+K
  3. Error dialog with "Auto-Repair" button
  4. User clicks "Auto-Repair"
  5. Venv rebuilt
  6. Daemon restarted
  7. Try hotkey again
  8. Works ✅

---

## Code References

### Key Files to Modify

1. **`Contextify/Contextify/LaunchAgentManager.swift`** (lines 8-169)
   - Add `validateVenv() -> VenvStatus` after line 26
   - Add `rebuildVenvFromSystem()` after line 87
   - Modify `copyDaemonAndVenvIfNeeded()` (lines 54-87) to use new validation
   - Add progress reporting

2. **`Contextify/Contextify/TerminalContentReader.swift`** (lines 136-158)
   - Replace error alert with accurate message
   - Add "Auto-Repair" button
   - Call LaunchAgentManager repair logic

3. **`scripts/iterm2_daemon.py`** (lines 171-186)
   - Improve error logging in `connect_iterm()`
   - Add version detection
   - Add actionable hints in error messages

4. **`Contextify/Contextify/ITerm2DaemonClient.swift`** (lines 11-33)
   - Update DaemonError descriptions
   - Add recovery suggestions

### Build Configuration

**Remove broken PythonVenv from bundle:**
- Xcode project → Contextify target → Build Phases → Copy Bundle Resources
- Remove `PythonVenv` reference
- Keep `iterm2_daemon.py`
- Keep `Python/` directory (has direct site-packages)

**Update build script if needed:**
- `scripts/bundle_python.sh` can stay (creates `Resources/Python/`)
- Remove any venv bundling steps

---

## Appendix: Log Samples

### Daemon Startup (Working)
```json
{"ts": 1759613031191, "level": "INFO", "event": "daemon_started",
 "socket": "/Users/rob/Library/Application Support/Contextify/run/daemon-2a211cd9.sock",
 "pid": 42717}
{"ts": 1759613031229, "level": "INFO", "event": "iterm2_connected", "attempt": 1}
```

### Connection Failures (Recurring Pattern)
```json
{"ts": 1759956438123, "level": "WARN", "event": "iterm2_connect_failed",
 "attempt": 1, "delay_s": 1, "err": "no close frame received or sent"}
{"ts": 1759956439168, "level": "WARN", "event": "iterm2_connect_failed",
 "attempt": 2, "delay_s": 2, "err": "no close frame received or sent"}
{"ts": 1759956441174, "level": "WARN", "event": "iterm2_connect_failed",
 "attempt": 3, "delay_s": 4, "err": "no close frame received or sent"}
{"ts": 1759956445179, "level": "ERROR", "event": "health_probe_reconnect_failed"}
```

### Health Probe Attempts (Every ~60s)
```json
{"ts": 1759956927647, "level": "INFO", "event": "health_probe_reconnecting"}
// ... 3 connection attempts ...
{"ts": 1759956934690, "level": "ERROR", "event": "health_probe_reconnect_failed"}
```

---

## Summary

### What We Know
1. ✅ Python IS bundled (but broken structure)
2. ✅ Daemon IS running
3. ❌ Venv uses symlinks (breaks portability)
4. ❌ Daemon can't connect to iTerm2 websocket
5. ❌ Error messages are misleading

### What Needs to Change
1. Remove bundled PythonVenv (broken)
2. Build venv on first run from system Python
3. Add health check and auto-repair
4. Fix/improve daemon connection logic
5. Update all error messages

### Release Impact
- **Timeline:** +2-3 days for venv auto-repair implementation
- **User Experience:** Better (clearer errors, auto-fix, progress feedback)
- **App Size:** Smaller (no broken venv bundle)
- **Reliability:** Higher (detects and repairs issues automatically)

### Next Steps
1. User: Check iTerm2 Python API settings
2. User: Test with iterm2 2.10
3. Dev: Implement venv validation and auto-repair
4. Dev: Update error messages
5. Dev: Test clean install flow
6. Update release-readiness.md with findings

---

**Report Generated:** 2025-10-08
**Author:** Claude (Diagnostic Analysis)
**Review Status:** Ready for implementation
**Estimated Fix Time:** 2-3 days (P0 items only)
