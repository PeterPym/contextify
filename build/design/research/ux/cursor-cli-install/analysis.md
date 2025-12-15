# Cursor CLI Installation Analysis

**Date:** 2025-12-14
**Context:** Understanding why Cursor requires admin privileges for CLI installation

---

## Installation Flow (Screenshots)

### 1. Initial Onboarding Screen
- **File:** Screenshot 2025-12-15 at 10.03.33 AM.png
- **Shows:** Preferences setup with "Open Cursor from Terminal" section
- **Action:** "Install" button for `cursor` command
- **Note:** No indication of admin requirement at this stage

### 2. Admin Permission Dialog
- **File:** Screenshot 2025-12-15 at 10.03.38 AM.png
- **Shows:** System dialog warning
- **Text:** "Cursor will now prompt with 'osascript' for Administrator privileges to install the shell command."
- **Buttons:** Cancel, OK (blue)
- **Note:** This is Cursor's own warning BEFORE the system prompt

### 3. macOS Security Prompt
- **File:** Screenshot 2025-12-15 at 10.03.49 AM.png
- **Shows:** Standard macOS authentication dialog
- **Text:** "osascript wants to make changes."
- **Action:** Password entry required
- **User:** Rob Banagale
- **Note:** This is the actual system-level privilege escalation

### 4. Success Confirmation
- **File:** Screenshot 2025-12-15 at 10.03.54 AM.png
- **Shows:** Success dialog
- **Text:** "Shell command 'cursor' successfully installed."
- **Button:** "Reinstall" now available
- **Note:** User can reinstall if needed later

---

## Installation Location Analysis

### Where Cursor Installed

```bash
$ which cursor
/usr/local/bin/cursor

$ ls -la /usr/local/bin/cursor
lrwxr-xr-x  1 root  wheel  56 Dec 15 10:03 /usr/local/bin/cursor -> /Applications/Cursor.app/Contents/Resources/app/bin/code
```

**Key Findings:**
- **Location:** `/usr/local/bin/cursor`
- **Type:** Symlink to app bundle
- **Owner:** `root:wheel` (system-owned)
- **Target:** `/Applications/Cursor.app/Contents/Resources/app/bin/code`
- **Why admin?** Writing to `/usr/local/bin` requires root privileges

---

## Why Admin Password Was Required

### The Core Issue: Directory Ownership

```bash
$ ls -la /usr/local/bin/
drwxr-xr-x  6 root  wheel  192 Dec 15 10:03 .
```

**Key finding:** `/usr/local/bin/` is owned by `root:wheel`

**What this means:**
- Only the `root` user (system administrator) can write to this directory
- Regular users can READ and EXECUTE files in it (that's why `which cursor` works)
- But creating/modifying files requires root privileges

**Why Cursor needed admin:**
1. Cursor wants to create a symlink at `/usr/local/bin/cursor`
2. Creating files in `/usr/local/bin/` requires root write access
3. macOS prompts for admin password to temporarily grant root access
4. Cursor creates the symlink as `root:wheel` (system-owned)
5. Done - now all users can execute `cursor` command

**Contrast with homebrew:**
- Homebrew changes `/usr/local/bin` ownership to your user on Intel Macs
- Or uses `/opt/homebrew/bin` with proper group permissions on Apple Silicon
- Once homebrew is installed, you can write to those directories WITHOUT admin
- That's why our auto-install works for homebrew users!

### Critical Question: Why Didn't Cursor Use Homebrew Paths?

**You have homebrew installed with writable permissions:**
```bash
$ ls -la /opt/homebrew/bin/
drwxrwxr-x@ 643 rob  admin   20576 Dec 14 21:24 .
```

This directory is owned by `rob:admin` - you could write there WITHOUT admin password!

**So why did Cursor still ask for admin and use `/usr/local/bin`?**

**Cursor's reasoning (likely):**
1. **Consistency** - `/usr/local/bin` exists on ALL Macs by default, homebrew doesn't
2. **Simplicity** - One path, one flow, works everywhere (no detection logic needed)
3. **User expectations** - Professional tools (Docker, VS Code) all request admin for `/usr/local/bin`
4. **Precedence** - `/usr/local/bin` often comes before `/opt/homebrew/bin` in PATH
5. **Universal** - Works even if user uninstalls homebrew later
6. **No edge cases** - Don't need to detect homebrew, check permissions, handle fallbacks

**The trade-off:**
- **Cursor:** Asks admin from EVERYONE for predictability
- **Our approach:** Avoid admin for 90% (homebrew users), show PATH warning for 10%

**Why our approach is still valid:**
- We optimize for the common case (homebrew installed)
- Graceful degradation with clear warning for edge case
- Simpler implementation (no admin auth flow)

## Why `/usr/local/bin` Instead of User Directory?

### Cursor's Choice: `/usr/local/bin` (Admin Required)

**Advantages:**
1. **Universal PATH** - `/usr/local/bin` is on PATH by default for ALL users on macOS
2. **No shell configuration needed** - Works immediately in any shell (bash, zsh, fish, etc.)
3. **System-wide availability** - Multiple user accounts can use `cursor` command
4. **Precedence** - `/usr/local/bin` comes before `/usr/bin` in default PATH (overrides system tools)
5. **Standard convention** - Follows Unix/macOS conventions for user-installed binaries
6. **Proven pattern** - Same as homebrew (`/usr/local/bin` on Intel, `/opt/homebrew/bin` on Apple Silicon)

**Disadvantages:**
- Requires admin password (one-time)
- User might decline permission

### Alternative: `~/bin` or `~/.local/bin` (No Admin)

**Advantages:**
- No admin password required
- User-specific installation
- Easier to clean up (just delete the file)

**Disadvantages:**
1. **Not on PATH by default** - User must manually add to shell config:
   ```bash
   # Add to ~/.zshrc or ~/.bashrc
   export PATH="$HOME/bin:$PATH"
   ```
2. **Shell restart required** - Must reload shell config or restart terminal
3. **Per-shell configuration** - Must add to EACH shell config (zsh, bash, fish)
4. **Easy to miss** - Users might not have `~/bin` created yet
5. **Not discoverable** - `which cursor` returns nothing until shell reloaded
6. **Multiple-step setup** - Install → Edit shell config → Reload shell
7. **Support burden** - Users asking "why doesn't `cursor` work?"

---

## Comparison with Our CLI Auto-Install

### Our Current Approach (DMG)

```swift
// CLICoordinator.swift:323-344
private func determineShimPath() -> URL {
  let fileManager = FileManager.default

  // App Store: always use ~/bin (no permissions needed)
  if Sandbox.isSandboxed {
    return fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("bin/contextify-query")
  }

  // DMG: prefer homebrew/local paths
  if fileManager.fileExists(atPath: "/opt/homebrew/bin") {
    return URL(fileURLWithPath: "/opt/homebrew/bin/contextify-query")
  }
  if fileManager.fileExists(atPath: "/usr/local/bin") {
    return URL(fileURLWithPath: "/usr/local/bin/contextify-query")
  }

  // Fallback: ~/bin
  return fileManager.homeDirectoryForCurrentUser
    .appendingPathComponent("bin/contextify-query")
}
```

**DMG Strategy:**
1. Try `/opt/homebrew/bin` (Apple Silicon homebrew) - **WILL FAIL without admin**
2. Try `/usr/local/bin` (Intel homebrew) - **WILL FAIL without admin**
3. Fallback to `~/bin` - **WILL SUCCEED but not on PATH**

**Problem:** Steps 1-2 will fail silently, fall back to `~/bin`, then user gets PATH warning

### Cursor's Approach

- **Single location:** `/usr/local/bin` (no fallback)
- **Upfront admin request:** Ask for password BEFORE attempting install
- **Clear UX:** Two-step dialog (warning + system prompt)
- **All or nothing:** Either succeeds with admin, or user cancels

---

## Recommendations for Contextify

### Option 1: Keep Current Approach (Conservative)
- **Pro:** Zero friction for most users (homebrew paths usually writable via homebrew group)
- **Pro:** PATH warning UI already implemented
- **Con:** Users without homebrew get `~/bin` and see warning
- **Con:** Inconsistent UX (some users auto-install, some see warning)

### Option 2: Cursor's Approach (Request Admin)
- **Pro:** Consistent UX - always works or user knowingly declines
- **Pro:** No PATH configuration needed
- **Pro:** Professional/expected for developer tools
- **Con:** Requires implementing admin auth flow (osascript, AuthorizationExecuteWithPrivileges)
- **Con:** Some users might decline (but then they know why it doesn't work)

### Option 3: Hybrid Approach
1. **Try homebrew paths first** (no admin) - silent attempt
2. **If fails, offer admin install** - "Install needs admin password for /usr/local/bin" dialog
3. **If declined, fall back to ~/bin** - with PATH warning

**UX Flow:**
```
Auto-install attempt → Fails (no write access)
    ↓
Show dialog: "Install 'contextify-query' to /usr/local/bin? (Admin password required)"
    ↓
User clicks "Allow" → Request admin → Install to /usr/local/bin → Success ✅
User clicks "Cancel" → Install to ~/bin → Show PATH warning ⚠️
```

### Option 4: Smart Detection (Recommended)

```swift
private func determineShimPath() -> URL {
  let fileManager = FileManager.default

  // App Store: always use ~/bin (no permissions needed)
  if Sandbox.isSandboxed {
    return fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent("bin/contextify-query")
  }

  // DMG: Check if we can write to system locations WITHOUT admin
  // This succeeds if user has homebrew installed and is in homebrew group
  let homebrewPaths = [
    "/opt/homebrew/bin",
    "/usr/local/bin"
  ]

  for path in homebrewPaths {
    if fileManager.isWritableFile(atPath: path) {
      return URL(fileURLWithPath: "\(path)/contextify-query")
    }
  }

  // No writable system paths - use ~/bin (no admin needed)
  // Show PATH warning in UI
  return fileManager.homeDirectoryForCurrentUser
    .appendingPathComponent("bin/contextify-query")
}
```

**Why this is better:**
- ✅ Zero friction for homebrew users (majority of developers)
- ✅ No admin prompt for homebrew users
- ✅ Graceful fallback to `~/bin` with clear PATH warning
- ✅ No complexity of admin auth flow
- ✅ Matches our design goal: "zero manual steps for DMG users"

---

## Technical Implementation Notes

### How Cursor Does Admin Auth

Looking at the screenshots, Cursor uses:
1. **osascript** - AppleScript runner (can request admin via "do shell script with administrator privileges")
2. **System dialog** - Native macOS authentication prompt
3. **Symlink creation** - Creates symlink owned by root:wheel

Likely implementation:
```applescript
do shell script "ln -sf '/Applications/Cursor.app/Contents/Resources/app/bin/code' '/usr/local/bin/cursor'" with administrator privileges
```

### Why We Don't Need This (Yet)

1. **Homebrew precedent** - Most developers have homebrew, which already handles `/opt/homebrew/bin` permissions
2. **~/bin fallback** - Graceful degradation with clear warning
3. **Complexity** - Admin auth adds code complexity and testing burden
4. **Edge case** - Only affects non-homebrew users (small minority of developer audience)

---

## Conclusion

**Cursor's choice of `/usr/local/bin` with admin requirement is the RIGHT choice for:**
- Maximum compatibility (works for all users, all shells, immediately)
- Professional UX (expected behavior for developer tools)
- Zero post-install configuration

**Our current approach is ALSO VALID because:**
- Most developers have homebrew (no admin needed)
- Graceful fallback to `~/bin` with warning
- Simpler implementation (no admin auth flow)
- Matches our "zero manual steps" goal for 90% of users

**Recommendation: Keep current approach for v1.0, consider Cursor's approach for v2.0**

The 10% of users without homebrew who get the PATH warning is acceptable for v1.0. If this becomes a support burden, we can add admin auth in a future release.

---

## Screenshots Stored

Original screenshots optimized and analyzed:
- `Screenshot 2025-12-15 at 10.03.33 AM.png` - Initial setup
- `Screenshot 2025-12-15 at 10.03.38 AM.png` - Admin warning dialog
- `Screenshot 2025-12-15 at 10.03.49 AM.png` - macOS auth prompt
- `Screenshot 2025-12-15 at 10.03.54 AM.png` - Success confirmation

Analysis document: `/tmp/cursor-cli-installation-analysis.md`
