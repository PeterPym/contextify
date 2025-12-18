# App Store CLI via Homebrew - Implementation Plan

**Date:** 2025-12-18
**Branch:** `feat/cli-auto-install`
**Status:** Ready for implementation

## Summary

App Store builds cannot include a functional CLI due to sandbox constraints (see `build/notes/appstore/cli-installation-sandbox-constraints.md`). The solution is to:

1. Distribute CLI via Homebrew for App Store users
2. Keep CLI embedded in DMG builds (works fine)
3. Update App Store UI to show Homebrew install instructions

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         DMG Build                                │
├─────────────────────────────────────────────────────────────────┤
│ • CLI embedded in app bundle (Contents/MacOS/contextify-query)  │
│ • Shim installed to /opt/homebrew/bin or /usr/local/bin         │
│ • Auto-install on first launch (homebrew users)                 │
│ • Admin dialog for non-homebrew users                           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      App Store Build                             │
├─────────────────────────────────────────────────────────────────┤
│ • CLI still embedded (for completeness) but NOT functional      │
│ • Settings UI shows Homebrew install instructions               │
│ • Detects if CLI installed via `which contextify-query`         │
│ • No Enable/Disable buttons - just instructions + status        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Homebrew Distribution                         │
├─────────────────────────────────────────────────────────────────┤
│ • Repo: github.com/PeterPym/homebrew-contextify                 │
│ • Formula downloads pre-built binary from GitHub releases       │
│ • Binary is Developer ID signed (not App Store signed)          │
│ • Installs to /opt/homebrew/bin/contextify-query                │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Current PR Cleanup (Do Now)

**Goal:** Merge DMG CLI improvements, defer App Store CLI to P4

1. **Revert App Store-specific code** that doesn't work:
   - Remove file picker logic from CLICoordinator (sandbox approach failed)
   - Remove shell script shim generation (underlying binary is sandboxed)
   - Keep bookmark storage code (might be useful later)

2. **Update App Store UI** to show "Coming Soon" or placeholder:
   ```swift
   if Sandbox.isSandboxed {
     Text("CLI features coming soon via Homebrew")
       .font(.caption)
       .foregroundStyle(.secondary)
   }
   ```

3. **Commit and merge** DMG improvements to main

### Phase 2: Homebrew Tap Setup (P4)

**Goal:** Create homebrew-contextify repo and formula

#### 2.1 Create Repository

```bash
# On GitHub: Create PeterPym/homebrew-contextify
# Clone locally
cd ~/code/projects
git clone git@github.com:PeterPym/homebrew-contextify.git
cd homebrew-contextify

# Create structure
mkdir Formula
touch Formula/contextify-query.rb
touch README.md
touch LICENSE
```

#### 2.2 Create Formula

File: `Formula/contextify-query.rb`

```ruby
class ContextifyQuery < Formula
  desc "CLI for querying Contextify database - enables Claude Code/Codex skills"
  homepage "https://contextify.sh"
  version "0.8.5"  # Match app version
  license "MIT"

  # Download pre-built binary from GitHub releases
  if Hardware::CPU.arm?
    url "https://github.com/PeterPym/contextify/releases/download/v#{version}/contextify-query-arm64.tar.gz"
    sha256 "PLACEHOLDER_ARM64_SHA256"
  else
    url "https://github.com/PeterPym/contextify/releases/download/v#{version}/contextify-query-x86_64.tar.gz"
    sha256 "PLACEHOLDER_X86_SHA256"
  end

  def install
    bin.install "contextify-query"
  end

  def caveats
    <<~EOS
      contextify-query has been installed.

      This CLI enables Contextify skills in Claude Code and Codex.
      Requires Contextify.app to be running for database access.

      Verify installation:
        contextify-query status

      For more info:
        https://contextify.sh/docs/cli
    EOS
  end

  test do
    # Just check it runs (will fail without db, but that's ok)
    system "#{bin}/contextify-query", "--help"
  end
end
```

#### 2.3 Build CLI Binary for Distribution

The CLI needs to be built OUTSIDE the app bundle, signed with Developer ID:

```bash
# In contextify-worker-bee repo
# Build standalone CLI (not embedded in app)
swift build -c release --product contextify-query

# Sign with Developer ID
codesign --force --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --options runtime \
  .build/release/contextify-query

# Notarize
xcrun notarytool submit contextify-query.zip \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple contextify-query

# Package for Homebrew
tar -czvf contextify-query-arm64.tar.gz contextify-query
shasum -a 256 contextify-query-arm64.tar.gz
```

#### 2.4 Release Workflow Integration

Add to `scripts/release/build.sh`:

```bash
# After building app, also build standalone CLI for Homebrew
build_homebrew_cli() {
  echo "Building standalone CLI for Homebrew..."

  # Build
  swift build -c release --product contextify-query

  # Sign with Developer ID (not App Store cert)
  codesign --force --sign "$DEVELOPER_ID_CERT" \
    --options runtime \
    .build/release/contextify-query

  # Package
  local version=$(get_version)
  local arch=$(uname -m)
  tar -czvf "build/contextify-query-${arch}.tar.gz" \
    -C .build/release contextify-query

  echo "Created: build/contextify-query-${arch}.tar.gz"
}
```

### Phase 3: App Store UI Update (P4)

**Goal:** Show Homebrew instructions in Settings > CLI tab

#### 3.1 Update CLISkillsSettingsTab.swift

```swift
case .disabled:
  if Sandbox.isSandboxed {
    // App Store: Show Homebrew instructions
    VStack(alignment: .leading, spacing: 12) {
      Text("Enable Contextify skills in Claude Code and Codex.")
        .font(.body)

      Text("Due to App Store sandbox restrictions, the CLI must be installed separately:")
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Text("brew install PeterPym/contextify/contextify-query")
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(Color(nsColor: .controlBackgroundColor))
          .cornerRadius(6)

        Button {
          "brew install PeterPym/contextify/contextify-query".copyToClipboard()
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
      }

      Text("Then verify: contextify-query status")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  } else {
    // DMG: existing Enable button flow
    ...
  }
```

#### 3.2 Detect Homebrew-Installed CLI

```swift
// In CLICoordinator
private static func findHomebrewCLI() -> String? {
  // Check if contextify-query is on PATH
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
  process.arguments = ["contextify-query"]

  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice

  try? process.run()
  process.waitUntilExit()

  guard process.terminationStatus == 0 else { return nil }

  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

  return path?.isEmpty == false ? path : nil
}

// Update computeState for App Store
private static func computeState() -> State {
  if Sandbox.isSandboxed {
    // App Store: check for Homebrew-installed CLI
    if let cliPath = findHomebrewCLI() {
      // Read version from CLI
      let version = readVersionFromCLI(at: cliPath) ?? "unknown"
      return .enabled(version: version, pathWarning: false)
    }
    return .disabled
  }

  // DMG: existing logic
  ...
}
```

#### 3.3 Update State Enum

```swift
enum State: Equatable {
  case disabled
  case installing
  case enabled(version: String, pathWarning: Bool)
  case enabledViaHomebrew(version: String)  // NEW
  case upgrading(from: String, to: String)
  case failed(error: String)
}
```

### Phase 4: Documentation & Website (P4)

1. **Create docs page:** `contextify.sh/docs/cli`
   - Installation instructions (DMG vs App Store)
   - Usage examples
   - Troubleshooting

2. **Update README** with CLI section

3. **Add to release notes** when shipping

## File Changes Summary

### Phase 1 (Current PR)
```
Contextify/Contextify/CLICoordinator.swift
  - Revert/simplify App Store code path
  - Keep DMG improvements

Contextify/Contextify/Settings/CLISkillsSettingsTab.swift
  - Show placeholder for App Store

build/notes/appstore/cli-installation-sandbox-constraints.md
  - Document investigation (DONE)
```

### Phase 2 (New Repo)
```
homebrew-contextify/
  Formula/contextify-query.rb
  README.md
  LICENSE
```

### Phase 3 (Contextify Repo)
```
scripts/release/build.sh
  - Add Homebrew CLI build step

Contextify/Contextify/CLICoordinator.swift
  - Add Homebrew detection
  - New state: enabledViaHomebrew

Contextify/Contextify/Settings/CLISkillsSettingsTab.swift
  - Full Homebrew UI
```

## Implementation Status (COMPLETED 2025-12-18)

All phases implemented in a single session:

1. **CLICoordinator.swift** - Added `enabledViaHomebrew` state, `findHomebrewCLI()`, `readVersionFromCLI()`
2. **CLISkillsSettingsTab.swift** - Added Homebrew instructions view, refresh button
3. **homebrew-contextify repo** - Created at github.com/PeterPym/homebrew-contextify
4. **Formula** - contextify-query.rb with v1.0.2 binary
5. **GitHub Release** - v1.0.2 with arm64 binary at PeterPym/contextify

## Coexistence Scenarios

### Scenario: App Store + Homebrew CLI

This is the intended flow for App Store users:
1. User installs Contextify from App Store
2. Opens Settings > CLI tab, sees Homebrew instructions
3. Runs `brew install PeterPym/contextify/contextify-query`
4. App detects CLI via `which contextify-query`, shows "Installed via Homebrew"

**Result:** Works correctly. Homebrew binary accesses database at standard location.

### Scenario: App Store + Homebrew CLI, Then Install DMG

If user has App Store version with Homebrew CLI, then installs DMG:

1. DMG auto-installs shim to `/opt/homebrew/bin/contextify-query` (same location)
2. DMG shim calls the DMG's embedded CLI binary
3. `which contextify-query` still finds CLI at same path
4. Both work because they access the same database

**Potential issue:** If user has `~/bin` in PATH before `/opt/homebrew/bin`:
- DMG might install to `~/bin` for non-homebrew users
- PATH order determines which is used
- Both point to the same database, so functionally equivalent

**Recommendation:** No special handling needed. The user will have CLI functionality regardless of which binary is used, since both access the same database.

### Scenario: DMG User Installs Homebrew CLI

If DMG user runs `brew install contextify-query`:
- Homebrew installs to `/opt/homebrew/bin/contextify-query`
- DMG shim might be at same path or `~/bin`
- `brew link` will warn about conflict if DMG shim is at same path
- User can `brew link --overwrite` to use Homebrew version

**Result:** Works fine. User might see link warning but can resolve easily.

## Testing Checklist

### DMG Build Testing
- [x] DMG CLI auto-install works (homebrew paths)
- [x] DMG admin dialog works (non-homebrew users)
- [x] Enable/Disable buttons work correctly
- [x] Version display correct
- [x] PATH warning shown when needed

### App Store Build Testing
- [x] App Store CLI tab shows Homebrew instructions
- [x] No Enable/Disable buttons (just instructions)
- [x] Copy button works for brew command
- [x] Refresh Status button works
- [x] Detects Homebrew-installed CLI correctly
- [x] Shows "Installed via Homebrew (vX.X.X)" when detected

### Homebrew Installation Testing
- [x] `brew tap PeterPym/contextify` works
- [x] `brew install contextify-query` installs binary
- [x] `contextify-query --version` shows correct version (1.0.2)
- [x] `contextify-query status` works with database
- [x] Error message helpful when database not found

### CLI UX Testing
- [x] `--version` flag works
- [x] Database not found error suggests App Store installation
- [x] Error messages are clear and actionable

## Full QA Procedure

### Prerequisites
- Clean macOS machine (or VM) without Contextify
- Homebrew installed

### Test 1: Fresh App Store Installation
```bash
# 1. Install from App Store (or use sandbox build)
# 2. Open Contextify, complete onboarding
# 3. Go to Settings > CLI
# 4. Verify: Shows Homebrew instructions, no Enable button
# 5. Copy brew command, run in terminal
brew install PeterPym/contextify/contextify-query
# 6. Click "Refresh Status" in app
# 7. Verify: Shows "Installed via Homebrew (v1.0.2)"
# 8. Test CLI
contextify-query status
contextify-query --version
```

### Test 2: Fresh DMG Installation
```bash
# 1. Install DMG build
# 2. Open Contextify
# 3. Verify: CLI auto-installs (check console logs)
# 4. Go to Settings > CLI
# 5. Verify: Shows "Installed (v1.0.2)" with Disable button
# 6. Test CLI
contextify-query status
which contextify-query  # Should be /opt/homebrew/bin/ or ~/bin/
```

### Test 3: Homebrew CLI Without App
```bash
# 1. On machine without Contextify
brew install PeterPym/contextify/contextify-query
# 2. Run CLI
contextify-query status
# 3. Verify: Shows helpful error message about installing Contextify
```

### Test 4: Coexistence (App Store + DMG)
```bash
# 1. Start with App Store version + Homebrew CLI working
# 2. Install DMG version
# 3. Verify: CLI still works
contextify-query status
# 4. Check which binary is being used
which contextify-query
```

## Timeline

1. **Phase 1:** Merge with current PR (now)
2. **Phase 2:** P4 - When ready to ship App Store with CLI
3. **Phase 3:** P4 - Same release as Phase 2
4. **Phase 4:** P4 - Post-release documentation

## Open Questions

1. **Version sync:** How to keep Homebrew formula version in sync with app releases?
   - Option A: Manual update formula on each release
   - Option B: CI automation to update formula
   - Recommendation: Start manual, automate later

2. **Universal binary:** Build fat binary (arm64 + x86_64) or separate?
   - Recommendation: Separate for smaller downloads, Homebrew handles arch

3. **CLI in App Store bundle:** Keep or remove?
   - Keep: Simpler build process, no Xcode changes
   - Remove: Cleaner, smaller bundle
   - Recommendation: Keep for now, remove in future cleanup

## References

- `build/notes/appstore/cli-installation-sandbox-constraints.md` - Full investigation
- `/Users/rob/code/projects/homebrew-filekitty/` - Example Homebrew tap
- [Homebrew Taps Documentation](https://docs.brew.sh/Taps)
- [Notarization Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
