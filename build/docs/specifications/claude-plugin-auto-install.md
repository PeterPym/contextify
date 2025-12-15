# Claude Plugin Auto-Install/Upgrade Specification

## Overview

Automatically install and upgrade the Contextify Claude Code plugin to eliminate manual setup steps and ensure plugin version always matches app version.

**Note:** The Claude Code plugin provides enhanced functionality (skills for deterministic search and context reinjection) but is **optional**. Contextify's core features (timeline monitoring, LLM summaries, transcript search) work without the plugin. The plugin is **recommended** for users who want to use Contextify's skills within Claude Code conversations.

## Goals

1. **Zero manual steps for DMG users** - Plugin installs automatically on first launch
2. **Minimal friction for App Store users** - One-time permission grant, then automatic
3. **Always in sync** - Plugin version matches app version
4. **Graceful degradation** - Fall back to manual instructions if auto-install fails
5. **Optional but recommended** - Plugin installation is recommended for full functionality but app works without it

## Architecture

### Plugin Location

**Bundled in app:**
- Path: `Contents/Resources/contextify-query/claude-plugin/`
- Version: Read from `.claude-plugin/plugin.json`
- Structure matches Claude Code plugin format

**Installed location:**
- Path: `~/.claude/plugins/cache/contextify/query/{version}/`
- Manifests:
  - `~/.claude/plugins/installed_plugins_v2.json` - tracks installed plugins
  - `~/.claude/plugins/known_marketplaces.json` - tracks marketplace sources (optional for local installs)

### Build Types

**DMG (unsandboxed):**
- Direct filesystem access to `~/.claude/plugins/`
- Auto-install runs immediately on app launch
- No user interaction required

**App Store (sandboxed):**
- Requires security-scoped bookmark for `~/.claude/plugins/`
- Permission requested during onboarding (after transcript access)
- Auto-install runs once permission granted

## Installation Flow

### DMG Auto-Install

**On app launch:**

1. **Check if auto-install needed:**
   - Read bundled version from `Contents/Resources/contextify-query/claude-plugin/.claude-plugin/plugin.json`
   - Read installed version from `~/.claude/plugins/installed_plugins_v2.json`
   - Compare: not installed OR installed version < bundled version

2. **Install/upgrade plugin:**
   ```
   - Create directory: ~/.claude/plugins/cache/contextify/query/{version}/
   - Copy contents: {app bundle}/claude-plugin/* → {install path}
   - Update installed_plugins_v2.json:
     {
       "version": 2,
       "plugins": {
         "query@contextify": [{
           "scope": "user",
           "installPath": "/Users/{user}/.claude/plugins/cache/contextify/query/{version}",
           "version": "{version}",
           "installedAt": "{ISO timestamp}",
           "lastUpdated": "{ISO timestamp}",
           "isLocal": true
         }]
       }
     }
   ```

3. **Skip marketplace setup:**
   - We install directly from bundle, not from GitHub marketplace
   - `known_marketplaces.json` not required for local installs
   - Plugin marked as `"isLocal": true`

4. **Log result:**
   - Success: `[PLUGIN-AUTO-INSTALL-SUCCESS] version={version}`
   - Skip: `[PLUGIN-AUTO-INSTALL-SKIP] installedVersion={version} bundledVersion={version}`
   - Error: `[PLUGIN-AUTO-INSTALL-ERROR] {error}`

### App Store Auto-Install

**Permission request during onboarding:**

**Current onboarding steps:**
1. Choose database location
2. Grant transcript access (Claude Code: `~/.claude/projects/`)
3. Grant transcript access (Codex: `~/.codex/sessions/`) - *if Codex detected*

**New step (conditional):**
4. Grant plugin directory access (`~/.claude/plugins/`) - *if Claude Code transcript access granted*
5. Grant plugin directory access for Codex (`~/.codex/plugins/`) - *if Codex transcript access granted AND Codex supports plugins*

**Permission flow:**

```swift
// After user grants Claude Code transcript access
if userGrantedClaudeCodeAccess {
  showPluginAccessRequest = true
}

// Permission request UI
"Grant Plugin Directory Access"
"Allow Contextify to install the Claude Code plugin automatically."
[Choose Folder] → Opens NSOpenPanel to ~/.claude/plugins/
```

**After permission granted:**
- Store security-scoped bookmark
- Run same auto-install logic as DMG (inside `accessProvider.withAccess()`)

**On subsequent launches:**
- Resolve bookmark for `~/.claude/plugins/`
- Run auto-install check inside security scope
- Install/upgrade if needed

### Upgrade Flow

**On every app launch:**

1. **Version check:**
   - Bundled version > installed version → Upgrade
   - Bundled version = installed version → Skip
   - Bundled version < installed version → Skip (user has newer version, don't downgrade)

2. **Upgrade process:**
   - Same as install, but overwrite existing directory
   - Update `lastUpdated` timestamp in manifest
   - Preserve `installedAt` timestamp

## UI Changes

### Settings > Permissions Tab

**New permissions (App Store only):**

**Claude Code Plugin Directory:**
- **Label:** "Claude Code Plugin Directory"
- **Path:** `~/.claude/plugins/`
- **Purpose:** "Automatically install and update the Contextify plugin"
- **Status:** Granted / Not Granted
- **Actions:** [Grant Access] [Revoke Access]
- **Shown when:** User has granted Claude Code transcript access

**Codex Plugin Directory** (future, when Codex supports plugins):
- **Label:** "Codex Plugin Directory"
- **Path:** `~/.codex/plugins/` (assumed path, TBD)
- **Purpose:** "Automatically install and update the Contextify plugin"
- **Status:** Granted / Not Granted
- **Actions:** [Grant Access] [Revoke Access]
- **Shown when:** User has granted Codex transcript access

**Note:** Skills are bundled inside the plugin directory, so permission to `~/.claude/plugins/` grants access to both plugin installation and skill execution. No separate `/skills/**` permission needed.

### Settings > CLI Tab

**DMG Build - Plugin Section:**

**When auto-installed successfully:**
```
┌─ Enable Claude Code plugin ─────────────────────────────────┐
│                                                               │
│ ✓ Plugin installed (version 0.0.1)                           │
│                                                               │
│ The plugin is automatically managed by Contextify.           │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**When auto-install failed:**
```
┌─ Enable Claude Code plugin ─────────────────────────────────┐
│                                                               │
│ ⚠️ Automatic installation failed                            │
│                                                               │
│ Manual installation required:                                │
│                                                               │
│ Step 1: Copy plugin folder                                   │
│ Location: {app bundle path}/claude-plugin                    │
│ [Show in Finder]                                              │
│                                                               │
│ Step 2: Install in Claude Code                               │
│ /plugin install {path to copied folder}                      │
│ [Copy command]                                                │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**App Store Build - Plugin Section:**

**When permission granted and auto-installed:**
```
┌─ Enable Claude Code plugin ─────────────────────────────────┐
│                                                               │
│ ✓ Plugin installed (version 0.0.1)                           │
│                                                               │
│ The plugin is automatically managed by Contextify.           │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**When permission not granted:**
```
┌─ Enable Claude Code plugin ─────────────────────────────────┐
│                                                               │
│ ⚠️ Plugin directory access required                         │
│                                                               │
│ Contextify needs access to ~/.claude/plugins/ to             │
│ automatically install and update the plugin.                 │
│                                                               │
│ [Open Permissions Settings]                                  │
│                                                               │
│ Or install manually:                                          │
│ (same manual instructions as DMG failure case)               │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**When user clicks [Open Permissions Settings]:**
- Switches to Settings > Permissions tab
- Scrolls to "Claude Code Plugin Directory" section
- User can grant access there
- After granting, can return to CLI tab where auto-install will run

### Onboarding Modal

**DMG Build:**
- **No onboarding step for CLI** - Auto-enabled by default
- CLI shim and plugin install automatically on first launch
- Users can disable in Settings > CLI tab

**App Store Build:**

**New step (after transcript permissions):**

**Page Title:** "Enable Contextify CLI"

**Content:**
```
☑ Enable CLI features (checked by default)

Get deterministic search and context reinjection in Claude Code conversations.

Required permissions:
☐ Plugin directory (~/.claude/plugins/)
  Used to add Contextify skills to Claude Code

The CLI shim will be installed to ~/bin

This may be disabled at any time in Settings.

[Continue]  [Back]
```

**Behavior:**
- **Checkbox pre-checked** (opt-out, not opt-in)
- If **checked**: Requests `~/.claude/plugins/` permission, installs shim + plugin
- If **unchecked**: Skips permission request, CLI disabled, can enable later in Settings
- No "Skip" button - user must check/uncheck the box explicitly
- "Back" button to return to previous step

**Permission flow when checked:**
1. User clicks [Continue] with box checked
2. NSOpenPanel opens to `~/.claude/plugins/`
3. User grants access → bookmark saved
4. Auto-install runs on first app launch
5. CLI enabled

**Permission flow when unchecked:**
1. User unchecks box, clicks [Continue]
2. No permission request
3. CLI disabled
4. Settings > CLI tab shows "Enable CLI" button → links to Permissions tab

**When Codex adds plugin support:**
- Show similar flow for Codex plugin
- Only shown if user granted Codex transcript access
- Same opt-out pattern (checked by default)

## Build Script Integration

### Clean/Reset Commands

Update `scripts/xc.sh` function `reset_state_for_bid()` to clean CLI installations:

**Add to function (after line 331, before "App state reset complete"):**

```bash
  # Clean CLI installations (shim + plugin)
  echo "  Cleaning CLI shim..."
  rm -f /opt/homebrew/bin/contextify-query 2>/dev/null || true
  rm -f /usr/local/bin/contextify-query 2>/dev/null || true
  rm -f "$HOME/bin/contextify-query" 2>/dev/null || true
  rm -f "$HOME/.local/bin/contextify-query" 2>/dev/null || true

  echo "  Cleaning Claude Code plugin..."
  rm -rf "$HOME/.claude/plugins/cache/contextify" 2>/dev/null || true

  # Update installed_plugins_v2.json to remove our plugin entry
  local plugins_manifest="$HOME/.claude/plugins/installed_plugins_v2.json"
  if [[ -f "$plugins_manifest" ]]; then
    if command -v jq >/dev/null 2>&1; then
      local temp_manifest="/tmp/contextify-plugins-$$.json"
      jq 'del(.plugins["query@contextify"])' "$plugins_manifest" > "$temp_manifest" 2>/dev/null || true
      if [[ -s "$temp_manifest" ]]; then
        mv "$temp_manifest" "$plugins_manifest"
      else
        rm -f "$temp_manifest"
      fi
    else
      # Fallback: just remove the whole file if jq not available
      rm -f "$plugins_manifest" 2>/dev/null || true
    fi
  fi
```

**Update help text:**
- Line 110: `"Reset app state (DB, prefs, bookmarks, CLI shim, plugin)"`
- Lines 155-157: Add "Remove CLI shim and plugin installations"
- Lines 162-164: Add "Remove CLI shim and plugin installations"

**Affected commands:**
- `dr` - Fast DMG cleanrun
- `da` - DMG cleanrun
- `ar` - App Store cleanrun
- `ca` - App Store cleanrun
- `reset-state` - Reset app state only
- `reset-all` - Reset permissions + state

**Testing:**
```bash
# Install CLI first
./scripts/xc.sh build

# Test reset
./scripts/xc.sh dr

# Verify cleanup
which contextify-query  # Should return nothing
test -d ~/.claude/plugins/cache/contextify && echo "FAIL" || echo "PASS"
```

## State Machine

### CLI State

The CLI is considered **enabled** if both shim and plugin exist. No separate UserDefaults flag needed.

**States:**
```
┌─────────────┐
│  Disabled   │ ← Initial state (App Store if no permission)
│  (Nothing   │ ← Or after user toggles off
│   exists)   │
└──────┬──────┘
       │ Auto-install (DMG) or User grants permission (App Store)
       ▼
┌─────────────┐
│  Installing │
│  (Background│
│   task)     │
└──────┬──────┘
       │ Success
       ▼
┌─────────────┐
│   Enabled   │ ← Shim + plugin exist
│  (version   │
│    X.Y.Z)   │
└──────┬──────┘
       │ User toggles off OR upgrade available
       ▼
┌─────────────┐   ┌──────────────┐
│   Enabled   │──▶│  Upgrading   │
│ (upgrading) │   │  (background)│
└─────────────┘   └──────┬───────┘
                         │ Success
       ┌─────────────────┘
       │
       ▼
┌─────────────┐
│  Failed     │ ← Install/upgrade error
│  (show      │    (user can retry or use manual instructions)
│   error)    │
└─────────────┘
```

**State Transitions:**

| From | To | Trigger | Action |
|------|-----|---------|--------|
| Disabled | Installing | App launch (DMG) or permission granted (App Store) | Start background install |
| Installing | Enabled | Install succeeds | Files exist, show version |
| Installing | Failed | Install fails | Show error + manual instructions |
| Enabled | Disabled | User toggles off | Remove shim + plugin files |
| Disabled | Installing | User toggles on | Re-install |
| Enabled | Upgrading | App upgraded, bundled version > installed | Start background upgrade |
| Upgrading | Enabled | Upgrade succeeds | Update manifest |
| Failed | Installing | User clicks retry | Re-attempt install |

**PATH Warning State (App Store only):**
- Substatus of "Enabled" when shim installed but `~/bin` not on PATH
- Show warning: "Add ~/bin to your PATH" with copy/paste command

### Coordinator Pattern

Following the same pattern as `AppStoreOnboardingCoordinator.swift`:

```swift
@MainActor
final class CLICoordinator: ObservableObject {
  static let shared = CLICoordinator()

  enum State: Equatable {
    case disabled
    case installing
    case enabled(version: String, pathWarning: Bool)
    case upgrading(from: String, to: String)
    case failed(error: String)
  }

  @Published private(set) var state: State
  @Published private(set) var isHandlingOperation: Bool = false

  private var lastCheckTime: Date?
  private let checkThrottleDuration: TimeInterval = 5.0

  // State transitions
  func enable() async
  func disable() async
  func checkAndUpgrade() async
  func refreshState()

  // State queries
  var isEnabled: Bool {
    if case .enabled = state { return true }
    return false
  }

  var needsPathWarning: Bool {
    if case .enabled(_, let pathWarning) = state {
      return pathWarning
    }
    return false
  }
}
```

**Key pattern elements:**
- Singleton with `@MainActor`
- `@Published` state property
- `isHandlingOperation` prevents UI races
- Throttled refresh to avoid expensive checks
- State computed from filesystem (shim/plugin existence)
- Logging at all transitions

## Implementation Components

### 1. `CLICoordinator.swift` (NEW)

Manages CLI enable/disable state following `AppStoreOnboardingCoordinator` pattern.

```swift
@MainActor
final class CLICoordinator: ObservableObject {
  static let shared = CLICoordinator()

  enum State: Equatable {
    case disabled
    case installing
    case enabled(version: String, pathWarning: Bool)
    case upgrading(from: String, to: String)
    case failed(error: String)
  }

  @Published private(set) var state: State
  @Published private(set) var isHandlingOperation: Bool = false

  private var lastCheckTime: Date?
  private let checkThrottleDuration: TimeInterval = 5.0

  private init() {
    self.state = Self.computeState()
  }

  func enable() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    state = .installing
    do {
      try await installShimAndPlugin()
      refreshState()
    } catch {
      state = .failed(error: error.localizedDescription)
    }
  }

  func disable() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    removeShimAndPlugin()
    state = .disabled
  }

  func checkAndUpgrade() async {
    guard case .enabled(let installedVersion, _) = state else { return }

    let bundledVersion = readBundledVersion()
    guard bundledVersion > installedVersion else { return }

    isHandlingOperation = true
    defer { isHandlingOperation = false }

    state = .upgrading(from: installedVersion, to: bundledVersion)
    do {
      try await upgradePlugin(to: bundledVersion)
      refreshState()
    } catch {
      state = .failed(error: error.localizedDescription)
    }
  }

  func refreshState() {
    let now = Date()
    if let lastCheck = lastCheckTime,
       now.timeIntervalSince(lastCheck) < checkThrottleDuration {
      return
    }

    state = Self.computeState()
    lastCheckTime = now
  }

  private static func computeState() -> State {
    // Check if shim exists
    guard let shimPath = findInstalledShim() else {
      return .disabled
    }

    // Check if plugin exists
    guard let pluginVersion = readInstalledPluginVersion() else {
      return .disabled
    }

    // Check if ~/bin is on PATH (App Store only)
    let pathWarning = shimPath.contains("/bin/") && !isHomeBindOnPath()

    return .enabled(version: pluginVersion, pathWarning: pathWarning)
  }

  private static func isHomeBinOnPath() -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let homeBin = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("bin").path
    return path.split(separator: ":").contains { String($0) == homeBin }
  }
}
```

### 2. Plugin Versioning

**Strategy:** Plugin version = App version (for now)

**Implementation:**
- Read from `Info.plist` → `CFBundleShortVersionString`
- During app launch, check bundled `claude-plugin/.claude-plugin/plugin.json`
- If versions differ during build, log warning

**Future:** Separate CLI versioning (contextify-query v1.x, plugin v1.x, app v2.x)

**Code:**
```swift
func readBundledPluginVersion() -> String {
  let pluginJsonPath = Bundle.main.resourceURL?
    .appendingPathComponent("contextify-query/claude-plugin/.claude-plugin/plugin.json")
  // Read and parse JSON version field
  // Returns app version if not found
  return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
}
```

### 3. Shim Installation Path Logic

**DMG Build:**
1. First choice: `/opt/homebrew/bin` (if directory exists)
2. Second choice: `/usr/local/bin` (if directory exists)
3. Fallback: `~/bin` (create if needed)

**App Store Build:**
- Always install to `~/bin` (no sandbox permission needed for user's home)
- Create `~/bin` if doesn't exist
- Check if `~/bin` on PATH → set pathWarning if not

**PATH Detection:**
```swift
func isHomeBinOnPath() -> Bool {
  let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
  let homeBin = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("bin").path
  return path.split(separator: ":").contains { String($0) == homeBin }
}
```

**PATH Warning UI:**
```
⚠️ ~/bin is not on your PATH

Add to ~/.zshrc or ~/.bashrc:
export PATH="$HOME/bin:$PATH"

[Copy Command]
```

### 4. Atomic Installation

To avoid partial installs if app crashes:

```swift
func installShimAndPlugin() async throws {
  // 1. Install to temp locations first
  let tempShim = FileManager.default.temporaryDirectory
    .appendingPathComponent("contextify-query-\(UUID())")
  let tempPlugin = FileManager.default.temporaryDirectory
    .appendingPathComponent("contextify-plugin-\(UUID())")

  try copyShim(to: tempShim)
  try copyPlugin(to: tempPlugin)

  // 2. Atomic moves to final locations
  let finalShim = determineShimPath()
  let finalPlugin = pluginCachePath()

  try FileManager.default.moveItem(at: tempShim, to: finalShim)
  try FileManager.default.moveItem(at: tempPlugin, to: finalPlugin)

  // 3. Update manifest (idempotent)
  try updatePluginManifest()
}
```

### 5. Rename `ClaudePluginDetector.swift`

- Current file created earlier: `ClaudePluginDetector.swift`
- Rename to: `CLICoordinator.swift` (matches pattern)
- Absorb detection logic into coordinator
- Single source of truth for CLI state

### 3. Update `AppStoreOnboardingView.swift`

- Add plugin permission step after transcript permissions
- Conditional: only shown if Claude Code/Codex transcript access granted
- Store bookmark for `~/.claude/plugins/` or `~/.codex/plugins/`

### 4. Update `CLISkillsSettingsTab.swift`

- Show installation status
- Show "Grant Permission" button for App Store if not granted
- Show manual fallback instructions if auto-install fails

## Error Handling

**Possible failures:**

1. **Bundle plugin missing** - Should never happen, but log error and show manual instructions
2. **Permission denied (App Store)** - Show "Grant Permission" button in Settings
3. **Manifest write failed** - Log error, show manual instructions
4. **Directory creation failed** - Log error, show manual instructions

**Fallback strategy:**

All failures fall back to showing manual installation instructions in Settings UI.

## Testing

### Unit Tests

**ClaudePluginInstaller tests:**
- `testBundledPluginVersionParsing` - Read version from bundle
- `testInstalledPluginVersionDetection` - Read version from manifest
- `testVersionComparison` - Upgrade/skip logic
- `testManifestUpdate` - JSON writing
- `testDirectoryCopy` - File operations
- `testPermissionCheck` - Security-scoped access (App Store)

### Manual Testing (DMG)

1. **Fresh install** - plugin auto-installs on first launch
   - Verify: Plugin files in `~/.claude/plugins/cache/contextify/query/{version}/`
   - Verify: `installed_plugins_v2.json` updated
   - Verify: Skills available in Claude Code
   - Check logs: `[PLUGIN-AUTO-INSTALL-SUCCESS]`

2. **Upgrade app** - plugin auto-upgrades on launch
   - Install v0.0.1, then upgrade app to v0.0.2
   - Verify: Plugin upgraded to v0.0.2
   - Verify: `lastUpdated` timestamp changed
   - Check logs: `[PLUGIN-AUTO-UPGRADE] from=0.0.1 to=0.0.2`

3. **Manually delete plugin** - auto-reinstalls on next launch
   - Delete `~/.claude/plugins/cache/contextify/`
   - Relaunch app
   - Verify: Plugin reinstalled
   - Check logs: `[PLUGIN-AUTO-INSTALL-SUCCESS]`

4. **Manually install newer version** - app doesn't downgrade
   - Run `/plugin install query@contextify` with v0.0.3 from GitHub
   - Launch app with bundled v0.0.2
   - Verify: Plugin stays at v0.0.3
   - Check logs: `[PLUGIN-AUTO-INSTALL-SKIP] installedVersion=0.0.3 bundledVersion=0.0.2`

### Manual Testing (App Store)

1. **Grant permission during onboarding** - plugin installs
   - Complete onboarding, grant plugin directory access
   - Verify: Plugin installed
   - Verify: Security-scoped bookmark saved
   - Check logs: `[PLUGIN-AUTO-INSTALL-SUCCESS] mode=appstore`

2. **Skip permission during onboarding** - manual instructions shown
   - Skip plugin permission step
   - Open Settings > CLI tab
   - Verify: Shows "⚠️ Plugin directory access required"
   - Verify: [Open Permissions Settings] button present

3. **Grant permission later in Settings** - plugin installs
   - Navigate Settings > Permissions tab
   - Grant "Claude Code Plugin Directory" access
   - Return to CLI tab
   - Verify: Plugin auto-installs
   - Check logs: `[PLUGIN-AUTO-INSTALL-SUCCESS]`

4. **Revoke permission** - falls back to manual instructions
   - Delete bookmark from Settings > Permissions
   - Check CLI tab
   - Verify: Shows permission required message
   - Verify: Manual instructions available

### E2E Test Suite Updates

**New test: `QA-XX-plugin-auto-install-dmg.sh`**

Validates DMG auto-install flow:
```bash
#!/bin/bash
# Test: Plugin auto-install on DMG build
# Expected: Plugin installs automatically, skills available

# 1. Clean state
rm -rf ~/.claude/plugins/cache/contextify/

# 2. Launch app
# Expected log: [PLUGIN-AUTO-INSTALL-SUCCESS]

# 3. Verify installation
test -d ~/.claude/plugins/cache/contextify/query/0.0.1/
test -f ~/.claude/plugins/installed_plugins_v2.json
grep -q "query@contextify" ~/.claude/plugins/installed_plugins_v2.json

# 4. Test upgrade
# (Replace bundled plugin with newer version, relaunch)
# Expected log: [PLUGIN-AUTO-UPGRADE]
```

**Updated test: `QA-14-onboarding-appstore.sh`**

Add validation for plugin permission step:
```bash
# After transcript permissions granted:
# - Verify plugin permission step shown
# - Grant access to ~/.claude/plugins/
# - Verify security-scoped bookmark saved
# - Verify plugin auto-installed
# - Check log: [PLUGIN-AUTO-INSTALL-SUCCESS] mode=appstore
```

**Updated test: `QA-XX-settings-permissions-tab.sh`**

Add validation for plugin permission UI:
```bash
# Settings > Permissions tab
# - Verify "Claude Code Plugin Directory" shown (if transcript access granted)
# - Test grant access flow
# - Test revoke access flow
# - Verify CLI tab updates when permission granted/revoked
```

### Log Validation Patterns

**Success logs:**
```
[PLUGIN-AUTO-INSTALL-SUCCESS] version=0.0.1
[PLUGIN-AUTO-INSTALL-SUCCESS] mode=appstore version=0.0.1
[PLUGIN-AUTO-UPGRADE] from=0.0.1 to=0.0.2
```

**Skip logs:**
```
[PLUGIN-AUTO-INSTALL-SKIP] reason=alreadyInstalled version=0.0.1
[PLUGIN-AUTO-INSTALL-SKIP] installedVersion=0.0.3 bundledVersion=0.0.2
```

**Error logs:**
```
[PLUGIN-AUTO-INSTALL-ERROR] error=bundleNotFound
[PLUGIN-AUTO-INSTALL-ERROR] mode=appstore error=permissionDenied
[PLUGIN-AUTO-INSTALL-ERROR] error=manifestWriteFailed path=~/.claude/plugins/installed_plugins_v2.json
```

### Testing Timeline

**Phase 1: DMG Implementation (validate before moving to App Store)**
1. Implement `ClaudePluginInstaller` for DMG
2. Manual testing (DMG scenarios 1-4)
3. Add unit tests
4. Validate logs match expected patterns
5. **E2E tests** - Add after manual validation confirms behavior

**Phase 2: App Store Implementation**
1. Extend installer for security-scoped access
2. Update onboarding modal
3. Update Settings > Permissions tab
4. Manual testing (App Store scenarios 1-4)
5. **E2E tests** - Add after manual validation confirms behavior

**Phase 3: E2E Test Suite**
1. Create `QA-XX-plugin-auto-install-dmg.sh`
2. Update `QA-14-onboarding-appstore.sh`
3. Create/update permissions tab test
4. Document expected logs in test assertions
5. Add to CI pipeline

**Note:** E2E tests should be added **after** manual testing validates all behaviors and log patterns are stable. This prevents test churn during implementation.

## Codex Support

**Current state:**
- Codex doesn't have plugin system yet
- Codex may add plugin support soon

**When Codex adds plugins:**
- Add similar auto-install for `~/.codex/plugins/`
- Bundle Codex plugin version in app
- Request permission in onboarding (if user granted Codex transcript access)
- Use same auto-install/upgrade logic

**File locations (when available):**
- Codex plugins: `~/.codex/plugins/` (assumed, not confirmed)
- Manifest format: TBD (will need to verify when Codex ships plugins)

## Migration Strategy

### Backwards Compatibility - Force Bundled Version

**Strategy:** Always use bundled version, overwrite any manual installations.

**Rationale:**
- Ensures compatibility between app, CLI, and plugin
- Simplifies support (one version to debug)
- User's manual install is replaced transparently

**Implementation:**

On first launch after upgrade:

1. **Detect existing installation** (any source: marketplace, manual, previous auto-install)
2. **Compare versions:**
   - If bundled > installed → Auto-upgrade
   - If bundled = installed → Skip
   - If bundled < installed → **Still upgrade** (force our version for compatibility)
3. **Overwrite files** using atomic installation
4. **Update manifest** to mark as `"isLocal": true`
5. **Log migration:** `[PLUGIN-MIGRATION] Replaced version X.Y.Z with bundled X.Y.Z`

**Edge case - User on beta plugin from GitHub:**
- User intentionally installed v0.0.5-beta from GitHub
- App bundles v0.0.4
- We force downgrade to v0.0.4
- **Acceptable:** User can disable CLI in settings if they want to manage plugin manually

**Users who haven't installed plugin:**

On first launch:
1. Auto-install runs (DMG) or after permission granted (App Store)
2. Plugin ready to use
3. No manual steps required (DMG) or one permission grant (App Store)

## App Store Review Notes

Documentation for App Store Connect submission to explain permissions and file operations.

**What to include in review notes:**

```
PLUGIN DIRECTORY ACCESS (~/.claude/plugins/)

Contextify integrates with Claude Code (a developer CLI tool) by installing
a plugin that provides advanced search and context features.

What we do:
- Install plugin files to ~/.claude/plugins/cache/contextify/
- Update ~/.claude/plugins/installed_plugins_v2.json manifest
- Files are read by Claude Code when user runs /skill commands

Why we need permission:
- Claude Code's plugin directory is outside our sandbox
- User explicitly enables this feature during onboarding
- User can disable at any time in Settings

Alternative approach:
- User could manually copy files and run /plugin install commands
- We automate this for better UX
- Same end result, but automatic

Privacy:
- We only read/write our own plugin files
- We never access other plugins or Claude Code data
- Permission can be revoked anytime
```

**CLI SHIM INSTALLATION (~/bin/)**

```
We install a command-line tool (contextify-query) to ~/bin/ which is
in the user's home directory (no special permissions required).

This allows Claude Code to query Contextify's database during conversations.
The tool is bundled with our app and versioned with each release.
```

**NO NETWORK ACCESS REQUIRED**

```
Plugin installation is entirely local:
- Files copied from app bundle to ~/.claude/plugins/
- No GitHub clone or network requests
- No external dependencies
```

## Open Questions (RESOLVED)

~~1. Should we force-upgrade if user has newer version from GitHub?~~
- **RESOLVED:** Yes, force bundled version for compatibility

~~2. Should we clean up old versions?~~
- **RESOLVED:** Leave cleanup to Claude Code

~~3. What if Claude Code changes plugin manifest format?~~
- **RESOLVED:** Detect format changes, fall back to manual

~~4. Should onboarding permission request be optional or required?~~
- **RESOLVED:** Optional (checkbox checked by default)

## Timeline

**Phase 1: DMG Auto-Install**
- Implement `ClaudePluginInstaller`
- Update Settings UI to show status
- Test install/upgrade flows

**Phase 2: App Store Auto-Install**
- Add onboarding permission step
- Implement security-scoped access
- Test permission grant/revoke flows

**Phase 3: Codex Support** (when available)
- Verify Codex plugin format
- Extend installer for Codex
- Add Codex permission to onboarding

## Success Metrics

- **DMG users:** 100% automatic installation (no manual steps)
- **App Store users:** >80% grant permission (20% use manual install)
- **Plugin version sync:** 100% of users have plugin version matching app version
- **Support tickets:** Reduction in "plugin not working" issues

## Risks

1. **Claude Code updates break our installer** - Mitigation: Version check, fallback to manual
2. **Users deny App Store permission** - Mitigation: Manual instructions always available
3. **Plugin conflicts with marketplace version** - Mitigation: Mark as local, use separate namespace
4. **Codex plugin format different than expected** - Mitigation: Wait for official release, verify format

## Design Pattern Documentation

After implementing `CLICoordinator`, document the coordinator pattern in:

**File:** `build/docs/design/swiftui-patterns.md`

**New Section:** "State Coordinators"

```markdown
### State Coordinators

For complex state management that spans multiple views, use the Coordinator pattern
demonstrated in `AppStoreOnboardingCoordinator` and `CLICoordinator`.

**Pattern:**
- `@MainActor final class` with `ObservableObject`
- Singleton via `static let shared`
- `@Published` state property (usually an enum)
- `@Published isHandlingOperation` to prevent UI races
- Throttled refresh for expensive operations
- State computed from persistence layer, not stored separately
- Logging at all state transitions

**Example:**
```swift
@MainActor
final class FeatureCoordinator: ObservableObject {
  static let shared = FeatureCoordinator()

  enum State: Equatable {
    case idle
    case working
    case complete
    case failed(String)
  }

  @Published private(set) var state: State
  @Published private(set) var isHandlingOperation: Bool = false

  private var lastCheckTime: Date?
  private let checkThrottleDuration: TimeInterval = 5.0

  private init() {
    self.state = Self.computeState()
  }

  func performAction() async {
    isHandlingOperation = true
    defer { isHandlingOperation = false }

    state = .working
    // ... do work
    refreshState()
  }

  func refreshState() {
    let now = Date()
    if let lastCheck = lastCheckTime,
       now.timeIntervalSince(lastCheck) < checkThrottleDuration {
      return
    }

    state = Self.computeState()
    lastCheckTime = now
  }

  private static func computeState() -> State {
    // Read from persistence, not in-memory flag
    // e.g., check if files exist, read UserDefaults, etc.
  }
}
```

**When to use:**
- State affects multiple views
- State needs to survive view lifecycle
- Expensive state computation (file I/O, etc.)
- Need to prevent concurrent operations

**When NOT to use:**
- Simple view-local state → use `@State`
- Simple shared state → use `@ObservedObject` or `@EnvironmentObject`
- One-time operations → use `.task` modifier

**References:**
- `AppStoreOnboardingCoordinator.swift` - Onboarding wizard state
- `CLICoordinator.swift` - CLI enable/disable state
```

## Related Documentation

- `build/docs/architecture/transcript-access-security.md` - Security-scoped bookmark pattern
- `build/docs/components/onboarding.md` - Onboarding flow (needs update)
- `build/docs/design/swiftui-patterns.md` - SwiftUI patterns (add coordinator pattern)
- `contextify-query/claude-plugin/` - Bundled plugin source
- `scripts/lib/cleanup.sh` - Shared cleanup functions
