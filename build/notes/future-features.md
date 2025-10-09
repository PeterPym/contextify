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

### Internationalization
**Priority:** P2

**Goal:** Support multiple locales for timeline completion detection and display.

**Work required:**
- Localize ack/deny lexicons and completion tokens
- Add locale-aware normalization (Unicode punctuation, RTL)
- Add tests per supported locale

**Acceptance criteria:**
- [ ] Completion detection works with localized "yes", "no", "ok", "done" equivalents
- [ ] Unicode punctuation handled correctly (e.g., fullwidth punctuation in CJK)
- [ ] RTL languages display correctly
- [ ] Test coverage for each supported locale (en, es, fr, de, ja, zh, ar minimum)

**Effort:** Medium
**Value:** Medium (enables international users)

---

### Local Storage for Timeline
**Priority:** P2

**Goal:** Persist `TimelineEntry` data for session continuity across app restarts.

**Work required:**
- Persist `TimelineEntry` objects to local storage (JSON, SQLite, or UserDefaults)
- Define schema migration strategy for future timeline changes
- Default `isCompletion` to `false` when missing from older stored entries
- Add debug toggle to switch between "live recompute" and "load from storage"

**Acceptance criteria:**
- [ ] Timeline persists across app restarts
- [ ] Entries load quickly (< 100ms for 1000 entries)
- [ ] Schema migrations handle missing fields gracefully
- [ ] Debug toggle allows testing both modes
- [ ] Storage location documented (likely `~/Library/Application Support/Contextify/timeline.json`)

**Effort:** Medium
**Value:** High (critical for production use)

---

## 🟢 Nice to Have - Compose Features

### Global Hotkey Focus Textarea
**Priority:** P1

Always focus the compose window when the global hotkey (Cmd+Shift+K+K) is triggered, even if there's no text yet in the input field. Currently requires text in the field to focus; should focus unconditionally to improve UX. User should be able to hit the hotkey and immediately start typing without manually clicking the textarea.

**Effort:** Small
**Value:** High

---

### Toast Feedback For Missing Input
**Priority:** P2

When the capture hotkey runs but `ClaudeCodeParser` finds no usable text, show a toast so the user knows nothing was captured. Right now the failure path is silent. Use the existing toast overlay in `ContentView` for consistency (e.g., "No command detected. Try selecting the region you want to capture.").

**Effort:** Small
**Value:** Medium

---

### Lock Target Terminal Tab
**Priority:** P2

Allow users to pin the iTerm2 tab/window that receives commands. Today we always target `current window/current session`, which can be the wrong buffer if the user switches panes. Add a "Lock Target" action that records the session's UUID via iTerm2 API; subsequent sends should address that session explicitly. Provide UI feedback (e.g., "Target: Tab X (locked)" with a quick unlock option).

**Effort:** Medium
**Value:** High

---

### Codex Pane Support
**Priority:** P2

The new Codex UI in iTerm2 renders input differently; the parser fails. Investigate how the buffer is exposed (scrollback vs. structured regions) and update `ClaudeCodeParser` so captures in Codex don't return empty. Ensure both send and capture pathways behave identically between classic terminal tabs and Codex tabs.

**Effort:** Medium
**Value:** Medium

---

### Live Mirror: Terminal Prompt ↔ Compose Textarea
**Priority:** P3 (Interesting Experiment)

Continuously sync the current state of the iTerm2 input prompt with the Contextify compose textarea in real-time. Bidirectional mirroring: typing in either location updates the other instantly. This would allow editing complex commands in Contextify's larger textarea while seeing live updates in terminal. Could be toggled on/off via preference. Technical approach: Use iTerm2 API to read/write current prompt buffer on a polling interval (50-100ms) or via change notifications if available. Show visual indicator when mirroring is active (e.g., sync icon or "Live" badge).

**Effort:** Large
**Value:** Low (experimental)

---

### Git Status Glance in HUD
**Priority:** P2

Next to the branch display, surface high-level repository state: staged vs unstaged counts, ahead/behind main (via `git status --porcelain=v2` and `git rev-list --left-right`), and highlight risky states (e.g., committing on `main` or detached HEAD). Ideally refresh when the HUD opens and when the watcher detects changes, so the summary stays current without manual git commands.

**Effort:** Medium
**Value:** High

---

### Prompt Template Quick Actions
**Priority:** P2

Add a horizontal set of icon buttons in the main app header, right-justified after the folder/branch display. Each icon represents a prompt template that, when clicked, inserts pre-written template text into the compose textarea. Templates use placeholder syntax (e.g., `{{problem specification}}`) that users can fill in with specifics.

**Initial Template: Technical Debug Brief Generator**
- Icon: 📋 document.on.clipboard (or lightbulb.fill)
- Prompt: "Write a detailed technical brief on {{problem specification}} to /tmp/ as a markdown file. For example, at a high level we are trying to {{high-level goal}}. Yet the {{component or system}} we've devised for this task is not behaving as expected. Include a list of all files related to the problem, with complete filepaths. Include 1-3 sentences for each describing their relationship to this problem. Prepend this file with a system prompt that would allow an LLM to easily take up the context provided and solve for the answer to the problem. After creating this, append the contents of each file listed in the related files section using shell commands or python. Do not read each file into context."

**Future Template Ideas:**
- 🧪 Test Generation: "Write comprehensive tests for {{component}}"
- 📊 Performance Analysis: "Analyze performance bottlenecks in {{system}}"
- 🔧 Refactor Plan: "Create refactoring plan for {{code area}} to improve {{quality aspect}}"
- 📝 Documentation: "Generate user-facing documentation for {{feature}}"
- 🐛 Bug Report: "Investigate and document {{bug description}} with reproduction steps"

**Implementation:**
- Templates stored as JSON/plist in app bundle or user preferences
- Support custom user-defined templates via settings
- Smart placeholder highlighting
- Tab key to jump between placeholders
- Optional: Auto-detect context from current file/selection to pre-fill placeholders

**Effort:** Medium
**Value:** High

---

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

## 🟢 Terminal Support Expansion

### Terminal.app Support
**Priority:** P2 (After iTerm2 polished)

**Current state:**
- ✅ AppleScript fallback exists for Terminal.app (TerminalContentReader.swift:146-176)
- ✅ Basic text capture works (slower than daemon, but functional)
- ❌ Text replacement mode not implemented
- ❌ Parsing may differ from iTerm2 output format
- ❌ Not tested/validated as primary use case

**Why Terminal.app is actually easier than iTerm2:**
1. **No Python dependency** - Native AppleScript API is excellent
2. **No daemon complexity** - Direct AppleScript calls work fine
3. **Simpler text manipulation** - AppleScript can directly set terminal content
4. **Already partially working** - Just needs polish and testing

**Expected performance:**
- Read latency: 50-100ms (vs iTerm2 daemon's 10ms)
- Still feels instant to users
- Much better than 1-2s legacy Python subprocess

**Work required:**

1. **Enhance AppleScript reader:**
   ```swift
   // Improve Terminal.app content reading
   private func readFromTerminalAppUsingAppleScript() -> String? {
       let script = """
       tell application "Terminal"
           get contents of selected tab of front window
       end tell
       """
       return executeAppleScript(script, appName: "Terminal")
   }
   ```

2. **Implement text replacement:**
   ```applescript
   tell application "Terminal"
       tell selected tab of front window
           -- Clear current input (send Ctrl+U)
           do script (ASCII character 21) in it

           -- Insert new text (don't execute)
           set contents to "new command text"
       end tell
   end tell
   ```

3. **Parser compatibility:**
   - Verify ClaudeCodeParser works with Terminal.app output
   - Terminal.app may format text differently than iTerm2
   - Test multi-line commands, ANSI colors, etc.

4. **Testing:**
   - Capture Claude Code input from Terminal.app
   - Send text back with replace mode
   - Verify undo/history works
   - Edge cases: empty prompt, multi-line, backgrounded app

**Acceptance criteria:**
- [ ] Text capture works in Terminal.app (<100ms P95)
- [ ] Text replacement clears input before inserting
- [ ] ClaudeCodeParser extracts input correctly
- [ ] Undo/history works same as iTerm2
- [ ] No errors on empty prompts or multi-line input
- [ ] Preference to set default terminal app (iTerm2 vs Terminal.app)

**Effort:** Small-Medium (1-2 hours)
**Value:** High (expands user base to all macOS users, not just iTerm2 users)

**Notes:**
- Terminal.app is the default macOS terminal
- Many users prefer it for simplicity
- AppleScript is more reliable than Python across macOS versions
- Could be implemented in parallel with iTerm2 polish

---

### Other Terminal Emulators
**Priority:** P3 (Nice to have)

**Potential targets:**
- **Warp:** Modern terminal with API - May have better integration than AppleScript
- **Kitty:** GPU-accelerated - Likely needs Accessibility API fallback
- **Alacritty:** Minimal terminal - Accessibility API only
- **Hyper:** Electron-based - May support AppleScript or custom protocol

**General approach for unknown terminals:**
1. Try iTerm2 daemon (only works for iTerm2)
2. Try Terminal.app AppleScript (works for some)
3. Fall back to Accessibility API (works for all, but slower and unreliable)

**Effort:** Medium per terminal
**Value:** Low (iTerm2 + Terminal.app cover 95%+ of users)

**Decision:** Focus on iTerm2 (daemon) and Terminal.app (AppleScript) first. Others can be added based on user demand.

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
