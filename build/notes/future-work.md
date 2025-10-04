# Future Work & TODO

This document tracks work items for Contextify, organized by priority and category. Use this instead of GitHub issues for planning.

---

## 🔴 Critical - Build & Infrastructure

### Bundle Daemon Resources in App
**Priority:** P0 (Blocker for production)

**Current state:**
- ✅ Daemon works with manually installed files in `~/Library/Application Support/Contextify/`
- ❌ Daemon script (`iterm2_daemon.py`) not bundled in app Resources
- ❌ Python venv not bundled in app Resources

**Required:**
1. Create release Python venv:
   ```bash
   rm -rf dist/PythonVenv
   python3 -m venv dist/PythonVenv
   dist/PythonVenv/bin/pip install --upgrade pip
   dist/PythonVenv/bin/pip install 'iterm2==2.7'
   ```

2. Add to Xcode project:
   - Add `scripts/iterm2_daemon.py` to Resources in Xcode
   - Add `dist/PythonVenv` as folder reference to Resources

3. Verify bundled in app:
   ```bash
   ls -l .derived/Build/Products/Debug/Contextify.app/Contents/Resources/iterm2_daemon.py
   ls -l .derived/Build/Products/Debug/Contextify.app/Contents/Resources/PythonVenv/bin/python3
   ```

4. Update LaunchAgentManager to use bundled resources

**Acceptance criteria:**
- [ ] Build via `bash scripts/xc.sh build` bundles all resources
- [ ] Build via Xcode Run button bundles all resources (same as script)
- [ ] LaunchAgent uses bundled venv/daemon without manual setup
- [ ] Fresh install works without manual file copying

---

### Verify Build Script ↔️ Xcode Parity
**Priority:** P0

**Goal:** Ensure `bash scripts/xc.sh build` and Xcode Run button produce identical builds.

**Test:**
1. Clean build via script:
   ```bash
   bash scripts/xc.sh clean
   bash scripts/xc.sh build
   find .derived/Build/Products/Debug/Contextify.app/Contents/Resources -type f > /tmp/script-build.txt
   ```

2. Clean build via Xcode:
   - Product → Clean Build Folder
   - Product → Run
   ```bash
   find .derived/Build/Products/Debug/Contextify.app/Contents/Resources -type f > /tmp/xcode-build.txt
   ```

3. Compare:
   ```bash
   diff /tmp/script-build.txt /tmp/xcode-build.txt
   ```

**Acceptance criteria:**
- [ ] No differences in bundled resources
- [ ] No differences in compiled binaries (code signatures may differ)
- [ ] Both methods bundle daemon script and venv
- [ ] Document any intentional differences

---

### Add Swift Files to Xcode Project
**Priority:** P1

**Current state:**
- ✅ `LaunchAgentManager.swift` compiles (Swift allows untracked files)
- ✅ `ITerm2DaemonClient.swift` compiles
- ❌ Files not in Xcode project navigator
- ❌ Won't work for archive/release builds

**Required:**
1. Open `Contextify.xcodeproj` in Xcode
2. Add files to project:
   - `Contextify/Contextify/LaunchAgentManager.swift`
   - `Contextify/Contextify/ITerm2DaemonClient.swift`
3. Ensure "Contextify" target is checked
4. Verify clean build succeeds

**Acceptance criteria:**
- [ ] Files visible in Xcode project navigator
- [ ] Files have target membership set to "Contextify"
- [ ] Archive build succeeds
- [ ] No duplicate symbol errors

---

### CI/CD Integration
**Priority:** P2

**When CI is set up:**
1. Add venv creation step before xcodebuild:
   ```bash
   python3 -m venv dist/PythonVenv
   dist/PythonVenv/bin/pip install iterm2==2.7
   ```

2. Cache `dist/PythonVenv` keyed by dependencies (if using requirements.txt)

3. Verify bundled resources in CI:
   ```bash
   bash /tmp/verify-build.sh  # From QA testing
   ```

**Acceptance criteria:**
- [ ] CI builds include daemon resources
- [ ] CI runs automated smoke tests
- [ ] Failed builds provide clear error messages

---

## 🟡 Important - Features & Polish

### Performance Benchmarking
**Priority:** P1

**Goal:** Validate daemon achieves target latency improvements.

**Method:**
1. Baseline (legacy mode):
   ```bash
   defaults write dev.contextify DisableDaemonMode -bool true
   # Press Cmd+Shift+K+K 50 times, record latencies
   ```

2. Daemon mode:
   ```bash
   defaults delete dev.contextify DisableDaemonMode
   # Press Cmd+Shift+K+K 50 times, record latencies
   ```

3. Analyze:
   ```bash
   tail -100 ~/Library/Application\ Support/Contextify/logs/daemon.stderr.log | \
     grep latency_ms | jq -r '.latency_ms' | sort -n | \
     awk '{sum+=$1; values[NR]=$1} END {
       print "P50:", values[int(NR*0.5)];
       print "P95:", values[int(NR*0.95)];
       print "P99:", values[int(NR*0.99)]
     }'
   ```

**Acceptance criteria:**
- [ ] Daemon P50 < 20ms
- [ ] Daemon P95 < 30ms
- [ ] 85%+ improvement over baseline
- [ ] Document results in `build/notes/completed.md`

---

### Daemon Recovery Testing
**Priority:** P1

**Scenarios to test:**
1. **iTerm2 restart:**
   - Quit iTerm2 while daemon running
   - Wait 60s for health monitor
   - Restart iTerm2
   - Verify daemon reconnects automatically
   - Verify hotkey works after recovery

2. **Sleep/wake:**
   - Put Mac to sleep with daemon running
   - Wake after 5+ minutes
   - Verify daemon still responsive

3. **Daemon crash:**
   - Kill daemon process: `pkill -9 -f iterm2_daemon.py`
   - Verify LaunchAgent restarts it (KeepAlive)
   - Verify healthcheck passes within 30s

**Acceptance criteria:**
- [ ] Daemon survives all scenarios
- [ ] Health monitor detects and repairs connection
- [ ] Logs show recovery events
- [ ] Hotkey works after recovery

---

### Production Build & Notarization
**Priority:** P2

**When ready for distribution:**
1. Create Release build configuration
2. Enable hardened runtime
3. Sign with Developer ID certificate
4. Notarize with Apple
5. Create distributable DMG

**Acceptance criteria:**
- [ ] Release build includes all resources
- [ ] Daemon works in sandboxed environment (or document sandbox=NO requirement)
- [ ] Passes notarization
- [ ] Installs cleanly on fresh Mac

---

## 🟢 Nice to Have - Compose Features

### Text History & Recovery

**Undo/Restore Cleared Text:**
- Keep last N compose texts in memory with timestamps
- Cmd+Z to undo clear, or history dropdown
- Storage: In-memory only (don't persist across restarts)
- **Effort:** Small
- **Value:** Medium

**Draft History Ring:**
- Save timestamped drafts: `{text, timestamp, source, sessionName}`
- Navigate with Cmd+[ (previous) and Cmd+] (next)
- Show indicator: "Draft 3 of 5"
- Max 20 drafts, oldest gets evicted
- **Effort:** Medium
- **Value:** High for power users

**Auto-save on Replace:**
- When new hotkey press replaces existing text
- Save the replaced text to history automatically
- Toast: "Previous text saved to history (Cmd+Z to restore)"
- **Effort:** Small
- **Value:** Medium

---

### Enhanced Send Options

**Multi-target Send:**
- Send same text to multiple terminal tabs/sessions
- UI: Checkbox list of iTerm2 sessions
- Use case: Send command to all dev environment tabs
- **Effort:** Medium
- **Value:** Low (niche use case)

**Template System:**
- Save frequently-used prompts as templates
- Quick insert via dropdown or keyboard shortcut
- Variables: `{{PROJECT}}`, `{{BRANCH}}`, `{{DATE}}`
- Storage: UserDefaults or `~/Library/Application Support/Contextify/templates.json`
- **Effort:** Medium
- **Value:** Medium

**Syntax Highlighting:**
- Detect code blocks (```language```)
- Light syntax highlighting in textarea
- Toggle on/off in preferences
- **Effort:** Large (NSTextView customization)
- **Value:** Low (nice to have)

---

### Append vs. Replace Modes

**URL Parameter: `mode=append`:**
- Default: `mode=replace` (current behavior)
- Optional: `mode=append` adds to existing text with newline separator
- Use case: Building up multi-part prompt from multiple shell commands
- **Effort:** Small
- **Value:** Medium

**UI Toggle:**
- Button/menu to switch between replace and append modes
- Persists user preference
- **Effort:** Small
- **Value:** Medium

---

### Quality of Life

**Keyboard Shortcuts:**
- Cmd+K: Clear compose area
- Cmd+Return: Send (✅ already implemented)
- Cmd+Shift+Return: Send without clearing
- Cmd+,: Open preferences
- **Effort:** Small per shortcut
- **Value:** High

**Preferences Panel:**
- Auto-clear on send: yes/no
- History size: 0-50 drafts
- Default send mode: keystrokes / keystrokes-no-newline / tmpfile
- Font size for textarea
- Theme: Auto / Light / Dark
- **Effort:** Medium (full prefs UI)
- **Value:** High (enables customization)

**Window Behavior:**
- Remember window size/position
- Always on top toggle
- Hide dock icon option
- **Effort:** Small
- **Value:** Medium

**Target Session Intelligence:**
- Auto-refresh session name when iTerm2 tab switches
- Poll every N seconds or on app activation
- Show warning if target session closed
- "Pin" a specific session instead of always using "current"
- **Effort:** Medium
- **Value:** Medium

---

## 🔵 Maybe Someday - Restore Old Features

### File/URL Ingestion
**What it was:** Drag files onto app, or paste URL + click "Ingest"
**Behavior:** Copied file to `~/Contextify/outputs/ingest/`, created markdown artifact
**Restore as:** Collapsible section or menu item
**Effort:** Medium (UI + file handling)
**Value:** Low (original Contextify feature, but compose is main focus now)

### Session Management
**What it was:** "New Session" button created session ID (Session-001)
**Behavior:** All artifacts tagged with session, checkpoints organized by session
**Restore as:** Tag compose sends with session ID
**Effort:** Medium
**Value:** Low (unclear use case without full Contextify workflow)

### Checkpoints
**What it was:** "Checkpoint" button created timestamped markdown
**Behavior:** Snapshot of current session state
**Restore as:** "Save Draft" button that creates checkpoint with compose text
**Effort:** Small
**Value:** Medium (if combined with history feature)

### Output Management
**What it was:** "Reveal Outputs" button, showed last artifact
**Behavior:** Opened `~/Contextify/outputs` in Finder
**Restore as:** Show compose history as "outputs"
**Effort:** Small
**Value:** Low

---

## 📝 Notes

- See `build/notes/archive/2025-10-02-compose-panel.md` for removed modal compose details
- See `build/notes/current.md` for active work status
- See `build/notes/completed.md` for completed work history
- See `build/notes/archive/2025-10-03-python-daemon.md` for daemon implementation details

---

**Last updated:** 2025-10-04

### Window Flashing on Text Capture
**Priority:** P1 (UX polish)

When text is sent from terminal via hotkey, the Contextify window briefly disappears and reappears. This is due to aggressive window management code added to handle duplicate windows.

**Acceptance Criteria:**
- [ ] Window remains stable when receiving text via hotkey
- [ ] No visible flashing or disappear/reappear behavior
- [ ] Still prevents duplicate windows from appearing

**Investigation:**
- Check ComposePresenter/ComposeSheet window activation logic
- Review window lifecycle in response to URL scheme handling
- Consider less aggressive approach to duplicate window prevention

### Text Replacement in Terminal
**Priority:** P1 (UX improvement)

When sending text back to terminal from compose window, it should replace the current input rather than append.

**Acceptance Criteria:**
- [ ] Sending text replaces terminal input line (not append)
- [ ] Implement undo/recovery for replaced text (cache last N replacements)
- [ ] Add text recovery in compose window as well (drafts, auto-save)
- [ ] Consider Cmd+Z to restore previous terminal input

**Related:**
- Ties into broader text history/recovery feature (see Nice to Have section)
