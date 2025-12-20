# App Store CLI Installation Research

**Date:** 2025-12-15
**Context:** CLI auto-install admin fallback implementation (feat/cli-auto-install branch)
**Decision:** DMG-only admin install for now, App Store requires separate entitlement

---

## Executive Summary

**Problem:** How can Contextify's App Store build install CLI shims to `/usr/local/bin` when the user doesn't have homebrew?

**Finding:** osascript with admin privileges is **BLOCKED** in sandboxed apps, but Apple provides a special entitlement as an alternative.

**Solution (current):** DMG builds use osascript, App Store builds use `~/bin` (no changes)

**Solution (future):** Request `com.apple.developer.security.privileged-file-operations` entitlement from Apple

---

## Research Question

Can App Store builds use `osascript` with `administrator privileges` to install CLI shims to `/usr/local/bin`?

## Answer: No (But There's an Alternative)

### osascript with Admin Privileges

**DMG builds (unsandboxed):** ✅ **Works**
- osascript can request admin privileges
- User sees system password prompt
- Creates symlink owned by `root:wheel`
- Same approach as Cursor, Docker Desktop

**App Store builds (sandboxed):** ❌ **Blocked**
- App Sandbox fundamentally prevents privilege escalation
- osascript with `administrator privileges` does nothing in sandbox
- This is a security restriction with no workarounds
- Has been blocked since early macOS versions, still in effect 2025

**Sources:**
- [Running AppleScript with admin on sandboxed app](https://forum.xojo.com/t/running-applescript-with-admin-on-sandboxed-app/80614) - "AppleScript with admin privileges doesn't work when the app is sandboxed"
- [Why privileged commands may never be allowed](https://eclecticlight.co/2020/02/15/why-privileged-commands-may-never-be-allowed/) - Explanation of sandbox restrictions

---

## Alternative: Privileged File Operations Entitlement

### What It Is

Apple provides a **special entitlement** for App Store apps that need to perform privileged file operations:

**Entitlement:** `com.apple.developer.security.privileged-file-operations`

**How to get it:**
- Must be requested from Apple using a special form
- Only available for Mac App Store (NOT for Developer ID/DMG)
- Apple reviews and approves on case-by-case basis

**API:** `NSWorkspaceAuthorization` with `NSWorkspaceAuthorizationTypeCreateSymbolicLink`

**User experience:**
- Shows system permission dialog (similar to osascript)
- User enters password
- Creates symlink with elevated privileges
- Works within sandbox restrictions

**Sources:**
- [Mac Sandboxing: Privileged File Operations](https://bitsplitting.org/2018/11/15/mac-sandboxing-privileged-file-operations/) - Detailed explanation of the entitlement
- [Installing a command line tool from my sandboxed Mac app](https://developer.apple.com/forums/thread/130092) - Developer discussion and confirmation

### Real-World Example: BBEdit

BBEdit successfully uses this entitlement in their App Store version:

**What they do:**
- Install command-line tools (`bbedit`, `bbfind`, `bbdiff`) to `/usr/local/bin`
- Create symlinks pointing to tools inside BBEdit.app bundle
- Use `NSWorkspaceAuthorization` API with appropriate entitlement
- Fallback: Provide separate remedial installer for edge cases

**Sources:**
- [BBEdit command not found discussion](https://groups.google.com/g/bbedit/c/ZeW57B6AIKs) - Mentions App Store sandbox limitations
- Apple Developer Forums thread on sandboxed CLI installation

---

## Comparison of Approaches

| Approach | Distribution | Works? | User sees | Requires |
|----------|--------------|--------|-----------|----------|
| **osascript with admin** | DMG only | ✅ Yes | Password prompt | Unsandboxed app |
| **osascript with admin** | App Store | ❌ No | Nothing (blocked) | Sandbox prevents it |
| **NSWorkspaceAuthorization** | App Store only | ✅ Yes | Password prompt | Special entitlement from Apple |
| **~/bin install** | Both | ✅ Yes | PATH warning | Nothing |

---

## Why Other Apps Don't Use App Store

**VS Code:** DMG only (not on App Store)
**Docker Desktop:** DMG only (not on App Store)
**Cursor:** DMG only (not on App Store)

These apps likely avoid App Store due to:
1. Sandbox restrictions on CLI installation
2. Review process complexity
3. 30% revenue share
4. Update approval delays

**BBEdit** is a notable exception - they've successfully navigated this.

**Sources:**
- [Docker Desktop Mac install](https://docs.docker.com/desktop/setup/install/mac-install/) - DMG distribution only
- [Docker Mac permission requirements](https://docs.docker.com/desktop/setup/install/mac-permission-requirements/) - Discusses admin privileges

---

## Implementation Options for Contextify

### Option 1: DMG-only admin install ✅ **CURRENT CHOICE**

**What:**
- DMG builds: osascript with admin (implemented in feat/cli-auto-install)
- App Store builds: `~/bin` only (existing behavior, no changes)

**Pros:**
- No Apple approval needed
- Fast to implement (already done)
- Low risk

**Cons:**
- App Store users still see PATH warning

**When to use:**
- Now (immediate improvement for DMG users)
- Validate demand before investing in Apple entitlement

---

### Option 2: Request Apple Entitlement (P4 Future Work)

**What:**
- Request `com.apple.developer.security.privileged-file-operations` entitlement
- Implement `NSWorkspaceAuthorization` for App Store builds
- Both DMG and App Store offer admin install option

**Pros:**
- Complete solution for all users
- Professional UX (like BBEdit)
- No PATH warnings

**Cons:**
- Unknown approval timeline from Apple
- More complex implementation
- Might delay App Store resubmission
- Requires justification in review notes

**When to use:**
- After v1.0 ships to App Store
- If App Store users complain about PATH configuration
- When bandwidth available for entitlement request process

---

## Implementation Details (Option 2)

### How to Request Entitlement

1. Submit request form to Apple (exact URL not documented publicly)
2. Provide justification:
   - Developer tool that installs CLI for enhanced functionality
   - Similar to BBEdit's use case
   - Optional feature (app works without it)
   - User explicitly opts in
3. Wait for Apple review/approval

### Implementation with NSWorkspaceAuthorization

```swift
import Foundation

func installCLIWithPrivilegedAccess(source: URL, destination: URL) throws {
  let workspace = NSWorkspace.shared

  // Request authorization for symlink creation
  let authorization = try workspace.requestAuthorization(
    ofType: .createSymbolicLink
  )

  // Create symlink with elevated privileges
  try workspace.createSymbolicLink(
    atPath: destination.path,
    withDestinationPath: source.path,
    authorization: authorization
  )
}
```

**Note:** Exact API details may vary - refer to Apple documentation when implementing.

### App Store Review Notes

**If entitlement approved, add to review notes:**

```
PRIVILEGED FILE OPERATIONS ENTITLEMENT

Contextify uses the com.apple.developer.security.privileged-file-operations
entitlement to install an optional command-line tool.

What we do:
- Install 'contextify-query' CLI to /usr/local/bin (user-initiated)
- Creates symlink to tool inside app bundle
- Uses NSWorkspaceAuthorization API with CreateSymbolicLink type
- User sees system password prompt and explicitly approves

Why we need it:
- Contextify is a developer tool for AI coding sessions
- CLI enables advanced search and context features in Claude Code
- Installing to /usr/local/bin ensures CLI works in all shells
- Alternative (~/ bin) requires manual PATH configuration

Similar to:
- BBEdit (Mac App Store) - uses same entitlement for CLI tools
- VS Code, Docker Desktop (DMG only) - use osascript for same purpose

User control:
- Feature is optional (app works without CLI)
- User explicitly enables in Settings
- Can be disabled/uninstalled anytime
- Clear explanation before requesting privileges
```

---

## Recommendation

**Phase 1 (Complete):** Implement DMG-only admin install ✅
- Fast to ship
- Improves UX for 10% of DMG users (no homebrew)
- No Apple dependencies

**Phase 2 (Future P4):** Request App Store entitlement
- Only if App Store users complain about PATH configuration
- Requires bandwidth to handle entitlement request
- Unknown approval timeline (could be days or months)

**Metrics to watch:**
- Support tickets about PATH configuration (App Store users)
- User feedback on ~/bin install difficulty
- App Store user retention vs DMG user retention

---

## References

### Apple Documentation

- [Enabling App Sandbox](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) - App Sandbox overview
- Apple Developer Forums - Search for "privileged file operations" for real developer experiences

### Community Resources

- [Mac Sandboxing: Privileged File Operations](https://bitsplitting.org/2018/11/15/mac-sandboxing-privileged-file-operations/) - Best explanation of the entitlement
- [Xojo Forum: Running AppleScript with admin on sandboxed app](https://forum.xojo.com/t/running-applescript-with-admin-on-sandboxed-app/80614) - Confirms osascript blocked in sandbox
- [The Eclectic Light Company: Why privileged commands may never be allowed](https://eclecticlight.co/2020/02/15/why-privileged-commands-may-never-be-allowed/) - Security perspective

### Real-World Examples

- [BBEdit CLI Tools](https://www.barebones.com/support/bbedit/cmd-line-tools.html) - BBEdit's CLI installation
- [Docker Desktop Mac install](https://docs.docker.com/desktop/setup/install/mac-install/) - DMG-only approach
- [Docker Mac permission requirements](https://docs.docker.com/desktop/setup/install/mac-permission-requirements/) - Admin privilege patterns

---

## Next Steps (P4)

1. **Collect user feedback** - Monitor support requests about PATH configuration
2. **Research entitlement request process** - Find Apple's request form
3. **Draft justification** - Explain why Contextify needs this (like BBEdit)
4. **Submit request** - Apply for entitlement
5. **If approved:**
   - Implement `NSWorkspaceAuthorization` API
   - Update App Store build to offer admin option
   - Test thoroughly (requires real App Store build)
   - Update review notes
6. **If rejected:**
   - Keep DMG admin install
   - Improve ~/bin UX (better PATH instructions, shell detection)
   - Consider separate "CLI Installer" utility

---

## Related Documents

- **Specification:** `build/docs/specifications/claude-plugin-auto-install.md` - See section "3a. Admin Install Fallback"
- **Implementation:** `Contextify/Contextify/CLICoordinator.swift` - Admin install methods
- **Cursor Research:** `build/design/research/ux/cursor-cli-install/` - How Cursor handles CLI installation (DMG approach)
- **Plan:** `/Users/rob/.claude/plans/velvety-cooking-flame.md` - Implementation plan for this feature
