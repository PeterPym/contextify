---
todo_id: P1-SPARKLE
title: Sparkle Framework Implementation Briefing
type: implementation
date: 2025-11-25
status: ready
description: Code-level implementation details for DMG auto-updates via Sparkle (two targets, EdDSA signing, appcast, release workflow).
---
# Sparkle Framework Implementation - Technical Briefing v2

**Changes from v1:** Addressed blocking issues (two-target strategy, sign_update syntax), key management for CI, appcast versioning semantics, rollback playbook, and release workflow ordering.

## Executive Summary

Sparkle is the de facto standard for macOS app auto-updates outside the App Store. This briefing covers implementation for Contextify's DMG distribution with proper App Store/DMG separation.

---

## 1. Two-Target Strategy (App Store vs DMG)

**Critical:** Create two Xcode targets that share source files but differ in dependencies and Info.plist.

### Target Configuration

| Aspect | Contextify (App Store) | Contextify (DMG) |
|--------|------------------------|------------------|
| Bundle ID | `sh.contextify.Contextify` | `sh.contextify.Contextify` |
| Sparkle SPM | NOT linked | Linked |
| Swift Flags | `APPSTORE` | `SPARKLE` |
| Info.plist | Standard | + `SUFeedURL`, `SUPublicEDKey` |
| Sandbox | Yes | No* |
| Distribution | App Store Connect | Direct download |

*\*Note: Sandbox difference requires separate entitlements files. Current implementation uses single entitlements file - both may be sandboxed. See entitlements section below.*

**Bundle ID:** Both targets use same bundle ID (`sh.contextify.Contextify`). This means:
- MAS and DMG builds are the "same app" to macOS
- Users cannot run both simultaneously
- Preferences are shared
- This is intentional for simplicity; change if you need side-by-side installation.

### Xcode Setup

1. **Duplicate existing target:**
   - Right-click "Contextify" target → Duplicate
   - Rename to "Contextify DMG"
   - Original becomes "Contextify" (App Store)

2. **Add Sparkle SPM to DMG target only:**
   - File → Add Package Dependencies
   - URL: `https://github.com/sparkle-project/Sparkle`
   - Version: 2.8.x (pin to recent release)
   - Add to target: "Contextify DMG" only

3. **Set Swift Active Compilation Conditions:**
   - Contextify (App Store): `APPSTORE`
   - Contextify DMG: `SPARKLE`

4. **Separate Info.plist for DMG:**
   - Copy `Info.plist` to `Info-DMG.plist`
   - Add Sparkle keys to `Info-DMG.plist` only
   - Set DMG target's Info.plist File to `Info-DMG.plist`

### Info-DMG.plist Additions

```xml
<!-- Sparkle feed URL -->
<key>SUFeedURL</key>
<string>https://contextify.sh/appcast.xml</string>

<!-- Public EdDSA key for signature verification -->
<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY_HERE</string>

<!-- Check interval in seconds (default: 86400 = 24h) -->
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>

<!-- Don't auto-install without asking -->
<key>SUAutomaticallyUpdate</key>
<false/>

<!-- Disable anonymous system profiling -->
<key>SUEnableSystemProfiling</key>
<false/>
```

---

## 2. Swift Code Integration

**Use `#if SPARKLE` not `#if !APPSTORE`** - explicit is better than implicit.

### ContextifyApp.swift

```swift
import SwiftUI
#if SPARKLE
import Sparkle
#endif

@main
struct ContextifyApp: App {
    #if SPARKLE
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            #if SPARKLE
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            #endif
        }
    }
}
```

### CheckForUpdatesView.swift

```swift
#if SPARKLE
import SwiftUI
import Sparkle
import Combine

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
#endif
```

---

## 3. EdDSA Key Management

### Initial Key Generation (One-Time)

```bash
# From Sparkle package
./Sparkle/bin/generate_keys

# Output:
# A network service could not be created to publish the key.
# Your EdDSA (ed25519) public key to be included in your app's Info.plist:
#   o5/qHl9ILT...BASE64...==
#
# Your EdDSA (ed25519) private key, which is now stored in your Keychain.
```

**Store the public key in Info-DMG.plist as `SUPublicEDKey`.**

### Export Private Key for CI

```bash
# Export from Keychain to file
./Sparkle/bin/generate_keys -x ~/sparkle_private_key.txt

# The file contains:
# -----BEGIN EDDSA PRIVATE KEY-----
# BASE64_ENCODED_PRIVATE_KEY
# -----END EDDSA PRIVATE KEY-----
```

### Key Storage Locations

| Location | Key Type | Purpose |
|----------|----------|---------|
| macOS Keychain | Private | Local signing (Sparkle stores it here by default) |
| `~/sparkle_private_key.txt` | Private | Backup (encrypted, not in repo) |
| GitHub Secrets | Private (base64) | CI/CD signing |
| `Info-DMG.plist` | Public | App bundle (committed to repo) |

### GitHub Secrets Setup

```bash
# Encode private key for GitHub Secrets
base64 -i ~/sparkle_private_key.txt | pbcopy

# Add to GitHub:
# Settings → Secrets → Actions → New repository secret
# Name: SPARKLE_PRIVATE_KEY
# Value: (paste base64 encoded key)
```

**Key Rotation Warning:** Once you ship `SUPublicEDKey`, you must keep an EdDSA key matching it in ALL future updates. Sparkle supports adding new keys but NOT removing old ones.

---

## 4. Signing Updates

### Correct `sign_update` Syntax

**Wrong (deprecated):**
```bash
sparkle/bin/sign_update "App.dmg" -s "private_key"  # OLD SYNTAX
```

**Correct:**
```bash
# Using key file
sparkle/bin/sign_update "App.dmg" --ed-key-file path/to/private_key.txt

# Using stdin (recommended for CI)
# SPARKLE_PRIVATE_KEY is base64-encoded; decode and pipe
echo "$SPARKLE_PRIVATE_KEY" | base64 -d | sparkle/bin/sign_update "App.dmg" --ed-key-file -
```

### Python Signing Function

```python
import subprocess
import base64
import os
import re

def sign_dmg_for_sparkle(dmg_path: str, private_key_base64: str = None) -> str:
    """
    Sign DMG with EdDSA for Sparkle verification.

    Args:
        dmg_path: Path to notarized DMG
        private_key_base64: Base64-encoded private key (for CI)
                           If None, uses local keychain

    Returns:
        EdDSA signature string for appcast
    """
    sign_update = "sparkle/bin/sign_update"

    if private_key_base64:
        # CI mode: decode and pipe via stdin
        key_data = base64.b64decode(private_key_base64)
        result = subprocess.run(
            [sign_update, dmg_path, "--ed-key-file", "-"],
            input=key_data,
            capture_output=True,
            check=True,
        )
    else:
        # Local mode: Sparkle uses keychain automatically
        result = subprocess.run(
            [sign_update, dmg_path],
            capture_output=True,
            text=True,
            check=True,
        )

    # Output format: "sparkle:edSignature="BASE64_SIGNATURE" length="12345678""
    # Parse out just the signature
    output = result.stdout.decode() if isinstance(result.stdout, bytes) else result.stdout
    sig_match = re.search(r'sparkle:edSignature="([^"]+)"', output)
    if sig_match:
        return sig_match.group(1)

    raise ValueError(f"Could not parse signature from: {output}")
```

---

## 5. Appcast Structure

### Version Semantics

| Field | Maps To | Example | Purpose |
|-------|---------|---------|---------|
| `sparkle:version` | `CFBundleVersion` | `3` | Monotonic build number for comparison |
| `sparkle:shortVersionString` | `CFBundleShortVersionString` | `1.0.1` | User-visible version |

**Recommendation:** Use numeric build numbers for `sparkle:version` to enable proper comparison.

### Complete Appcast Example

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Contextify Updates</title>
    <link>https://contextify.sh/appcast.xml</link>
    <description>Most recent updates for Contextify</description>
    <language>en</language>

    <item>
      <title>Version 1.0.1</title>
      <pubDate>Mon, 25 Nov 2025 12:00:00 -0800</pubDate>

      <!-- Build number (monotonic, for Sparkle comparison) -->
      <sparkle:version>4</sparkle:version>

      <!-- User-visible version -->
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>

      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>

      <sparkle:releaseNotesLink>
        https://contextify.sh/release-notes/1.0.1.html
      </sparkle:releaseNotesLink>

      <enclosure
        url="https://contextify.sh/releases/Contextify-1.0.1.dmg"
        sparkle:edSignature="BASE64_SIGNATURE_HERE"
        length="12345678"
        type="application/octet-stream"
        sparkle:os="macos"
      />
    </item>

    <!-- Keep previous versions for rollback capability -->
    <item>
      <title>Version 1.0.0</title>
      <pubDate>Mon, 25 Nov 2025 10:00:00 -0800</pubDate>
      <sparkle:version>3</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>
        https://contextify.sh/release-notes/1.0.0.html
      </sparkle:releaseNotesLink>
      <enclosure
        url="https://contextify.sh/releases/Contextify-1.0.0.dmg"
        sparkle:edSignature="PREVIOUS_SIGNATURE"
        length="11426978"
        type="application/octet-stream"
        sparkle:os="macos"
      />
    </item>
  </channel>
</rss>
```

### Appcast Generation Function

```python
def generate_appcast_entry(
    version: str,           # e.g., "1.0.1"
    build_number: int,      # e.g., 4
    dmg_path: str,
    signature: str,
    release_notes_url: str,
    min_os: str = "26.0"
) -> str:
    """Generate XML entry for appcast."""
    size = os.path.getsize(dmg_path)
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S %z")
    dmg_filename = os.path.basename(dmg_path)

    return f"""
    <item>
      <title>Version {version}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{build_number}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>
        https://contextify.sh/release-notes/{version}.html
      </sparkle:releaseNotesLink>
      <enclosure
        url="https://contextify.sh/releases/{dmg_filename}"
        sparkle:edSignature="{signature}"
        length="{size}"
        type="application/octet-stream"
        sparkle:os="macos"
      />
    </item>
"""
```

---

## 6. Release Workflow

### Complete Release Sequence

```bash
# 1. Ensure clean git state
git status  # Should be clean

# 2. Bump version in Xcode (both targets)
# CFBundleShortVersionString: 1.0.1
# CFBundleVersion: 4 (increment from previous)

# 3. Build DMG target
bash scripts/xc.sh --target "Contextify DMG" Release build

# 4. Sign and notarize DMG
make sign-dmg
# Output: dist/Contextify.dmg (signed + notarized + stapled)

# 5. Sign for Sparkle (AFTER notarization, NEVER modify DMG after this)
# sign_update outputs: sparkle:edSignature="BASE64" length="12345"
# Parse out just the signature value
SIGNATURE=$(
  sparkle/bin/sign_update dist/Contextify.dmg \
    | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/'
)
echo "Signature: $SIGNATURE"

# 6. Upload DMG to server
scp dist/Contextify.dmg web@banagale.com:/var/www/contextify.sh/releases/Contextify-1.0.1.dmg

# 7. Create release notes HTML
# (manual or generate from CHANGELOG)

# 8. Update appcast.xml (signature must be raw base64 only)
python3 scripts/update_appcast.py --version 1.0.1 --build 4 --signature "$SIGNATURE"

# 9. Upload appcast
scp appcast.xml web@banagale.com:/var/www/contextify.sh/appcast.xml

# 10. Verify
curl -s https://contextify.sh/appcast.xml | head -30
```

**CRITICAL:** Do NOT rebuild or modify the DMG after step 5. If anything changes, re-run steps 4-5.

---

## 7. Bad Release Playbook

If you ship a broken update:

### Immediate Response (< 5 minutes)

1. **SSH to server:**
   ```bash
   ssh web@banagale.com
   cd /var/www/contextify.sh
   ```

2. **Edit appcast.xml - demote bad version:**
   ```bash
   # Option A: Remove bad item entirely
   vim appcast.xml  # Delete the bad <item> block

   # Option B: Keep for history, just ensure previous version is first
   # (Sparkle uses first matching item)
   ```

3. **Verify previous DMG exists:**
   ```bash
   ls -la releases/
   # Should see: Contextify-1.0.0.dmg, Contextify-1.0.1.dmg (bad), etc.
   ```

4. **Redeploy appcast:**
   ```bash
   # If you made changes locally
   scp appcast.xml web@banagale.com:/var/www/contextify.sh/appcast.xml
   ```

### Follow-up (< 1 hour)

5. **Update release notes for bad version:**
   ```html
   <!-- release-notes/1.0.1.html -->
   <h1>Version 1.0.1 - WITHDRAWN</h1>
   <p>This version has been withdrawn due to [issue].
      Please download 1.0.2 or wait for the automatic update.</p>
   ```

6. **Push hotfix if possible:**
   - Increment to 1.0.2
   - Fix the issue
   - Go through full release process

7. **Communicate:**
   - Update website with notice
   - Tweet if significant user impact

### Prevention

- Always keep at least 2 previous DMGs on server
- Never delete old appcast `<item>` entries (just add new ones at top)
- Test update flow locally before publishing appcast

---

## 8. Pre-Sparkle Users

Users who downloaded Contextify before Sparkle integration have no updater. They must manually download a new DMG.

**Website messaging:**
> "Running an older version? Download the latest to enable automatic updates."

**This is a v1 constraint.** Once they're on a Sparkle-enabled build, they're in the update pipeline.

---

## 9. Resolved Open Questions

| Question | Decision |
|----------|----------|
| SPM vs CocoaPods? | SPM - officially supported, cleaner |
| `#if !APPSTORE` vs targets? | Both: two targets + `#if SPARKLE` flag |
| Appcast structure? | Correct, added `sparkle:os` and version semantics |
| EdDSA key for CI? | GitHub Secrets (base64) + stdin piping |
| Time estimate? | 6-8 hours realistic for Phase 1 |
| Rollback strategy? | Documented playbook above |
| Delta updates? | Skip for now (11MB is fine) |
| macOS 26 / Swift 6 gotchas? | None known, pin Sparkle 2.8.x |
| Menu item sufficient? | Yes for v1 |
| Pre-Sparkle users? | Manual upgrade required, accept this |

---

## 10. Implementation Phases (Updated)

### Phase 1: Basic Integration (6-8 hours)
- Create DMG target with Sparkle SPM dependency
- Add `SPARKLE` compilation condition
- Create `Info-DMG.plist` with Sparkle keys
- Generate EdDSA key pair
- Implement `CheckForUpdatesView`
- Create initial `appcast.xml` on contextify.sh
- Test full update cycle locally

### Phase 2: Release Automation (2-3 hours)
- Update `scripts/release.py` for Sparkle signing
- Add `update_appcast.py` script
- Set up GitHub Secrets for CI
- Document bad release playbook in RELEASE.md

### Phase 3: Polish (2-3 hours, optional)
- Add Settings > Updates panel
- Add beta channel support (`appcast-beta.xml`)
- Consider phased rollout

---

## 11. File Changes Summary

| File | Change |
|------|--------|
| `Contextify.xcodeproj` | Add DMG target, Sparkle SPM |
| `Info-DMG.plist` | NEW - Sparkle keys |
| `ContextifyApp.swift` | `#if SPARKLE` updater init |
| `CheckForUpdatesView.swift` | NEW - Menu item |
| `scripts/release.py` | Sparkle signing integration |
| `scripts/update_appcast.py` | NEW - Appcast generator |
| `scripts/RELEASE.md` | Bad release playbook |
| `contextify.sh/appcast.xml` | NEW - Update feed |
| `contextify.sh/release-notes/` | NEW - Per-version HTML |

---

## References

- Sparkle Documentation: https://sparkle-project.org/documentation/
- Programmatic Setup: https://sparkle-project.org/documentation/programmatic-setup/
- EdDSA Migration: https://sparkle-project.org/documentation/eddsa-migration/
- Security & Reliability: https://sparkle-project.org/documentation/security-and-reliability/
- Publishing Updates: https://sparkle-project.org/documentation/publishing/
