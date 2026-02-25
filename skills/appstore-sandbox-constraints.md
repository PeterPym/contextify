# App Store Sandbox Constraints

When working on features that differ between DMG and App Store builds, remember these sandbox restrictions.

## Build Detection

```swift
if Sandbox.isSandboxed {
  // App Store build - restricted
} else {
  // DMG build - full access
}
```

## What the Sandbox Blocks

### Process Spawning
- **Cannot** run `Process()` to execute external binaries
- **Cannot** use `which`, `codesign`, shell commands
- **Cannot** spawn the CLI to read `--version`

### File System Access
- **Cannot** access paths outside sandbox without security-scoped bookmarks
- **Cannot** check if files exist at `/opt/homebrew/bin/`, `/usr/local/bin/`, etc.
- **Cannot** read/write to arbitrary paths
- `FileManager.default.isExecutableFile(atPath:)` fails for non-bookmarked paths

### What IS Allowed
- Access to app container (`~/Library/Containers/...`)
- Access to bookmarked directories (user-granted via file picker)
- Network requests
- Standard app functionality

## Entitlements (Contextify-AppStore.entitlements)

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
```

No process spawning entitlements, no arbitrary file access.

## Design Patterns for Dual-Build Features

### Pattern 1: Skip Detection in Sandbox
If you can't verify something, don't pretend to:

```swift
if Sandbox.isSandboxed {
  // Show instructions, let user verify manually in terminal
  return .showInstructions
} else {
  // Actually detect and show status
  return detectStatus()
}
```

### Pattern 2: Bookmark-Based Access
For file access, use security-scoped bookmarks:

```swift
try accessProvider.withAccess(for: .claude) { root in
  // File operations only work inside this closure
  let files = try FileManager.default.contentsOfDirectory(at: root, ...)
}
```

### Pattern 3: Graceful Degradation
Feature works in DMG, shows alternative in App Store:

```swift
if Sandbox.isSandboxed {
  Text("Install via Homebrew: brew install ...")
} else {
  Button("Enable") { installCLI() }
}
```

## CLI-Specific Constraints

The CLI (`contextify-query`) cannot be installed by the App Store build because:
1. Cannot write to `/opt/homebrew/bin/` or `/usr/local/bin/`
2. Cannot spawn processes to run the embedded CLI
3. Even if CLI is embedded, it inherits sandbox restrictions

**Solution:** Distribute CLI separately via Homebrew for App Store users.

## Common Mistakes

1. **Assuming `Process()` works** - It doesn't in sandbox
2. **Checking file existence outside container** - Always fails
3. **Trying to detect external tools** - Can't see outside sandbox
4. **Adding "Refresh" buttons that can't refresh** - Don't lie to users

## Testing

Always test both builds:
```bash
# DMG build (full access)
bash scripts/xc.sh --dist=dmg Debug build

# App Store build (sandboxed)
bash scripts/xc.sh --dist=appstore Debug build
```

Check which is running:
```bash
ps aux | grep Contextify | grep -v grep | head -1
# .derived-dmg/ = DMG build
# .derived-appstore/ = App Store build
```
