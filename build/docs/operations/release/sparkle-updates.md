# Sparkle Auto-Updates (DMG Distribution)

**Note:** This documentation applies only to releases that target the DMG channel. Releases with `target_channels: ["appstore"]` (App Store-only) do not require Sparkle configuration. Check targeting with `./scripts/release/context.sh`.

DMG builds use Sparkle for auto-updates. App Store builds use Apple's update mechanism.

## Architecture

```
User's Mac                           contextify.sh
-----------                          --------------
Contextify.app                       appcast.xml
  └── Sparkle framework              releases/
      └── checks SUFeedURL --------> Contextify-X.Y.Z.dmg
          every 24h
```

## Build Configuration

| Distribution | Swift Flag | Updates Via |
|--------------|------------|-------------|
| DMG | `-DSPARKLE` | Sparkle (appcast.xml) |
| App Store | `-DAPPSTORE_BUILD` | Apple |

Both flags use same codebase - Sparkle code is conditionally compiled.

## Key Files

| File | Purpose |
|------|---------|
| `Contextify/Info-Debug.plist` | Contains SUFeedURL, SUPublicEDKey |
| `Contextify/Info.plist` | Release plist (needs Sparkle keys for Release DMG) |
| `Contextify/Contextify/CheckForUpdatesView.swift` | Menu item |
| `Contextify/Contextify/ContextifyApp.swift` | Sparkle initialization |
| `website/appcast.xml` | Update feed |
| `scripts/sparkle/keygen.sh` | EdDSA key management |
| `scripts/sparkle/sign.sh` | Sign DMG for Sparkle |

## EdDSA Keys

**Public key** (in Info.plist):
```
zJ8lX0grlNGHwS0tFGbGs5Jv+roMWZv/mjlzXQXHO1M=
```

**Private key**: Stored in macOS Keychain (generated via `scripts/sparkle/keygen.sh`)

### Key Management

```bash
# Generate new keys (one-time setup, already done)
./scripts/sparkle/keygen.sh

# Export for CI (base64 encoded)
./scripts/sparkle/keygen.sh export
# Add to GitHub Secrets as SPARKLE_PRIVATE_KEY
```

## Release Workflow

### 1. Build Release DMG

```bash
# Use existing release script
python3 scripts/release/release.py --version X.Y.Z --yes
```

This creates `dist/Contextify-X.Y.Z.dmg` (signed + notarized).

### 2. Sign for Sparkle

```bash
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg
```

Output:
```
sparkle:edSignature="abc123..."
length="12345678"
```

### 3. Update Appcast

Edit `website/appcast.xml`. **Add new items at the TOP** (newest first).

#### Step-by-Step

1. **Generate RFC 2822 date:**
   ```bash
   date "+%a, %d %b %Y %H:%M:%S %z"
   # Output: Thu, 28 Nov 2025 14:30:00 -0800
   ```

2. **Determine build number:**
   - Check current highest in appcast.xml
   - Increment by 1 (monotonic integer: 1, 2, 3...)
   - This is `sparkle:version`, NOT the marketing version

3. **Copy signature and length** from sign.sh output

4. **Add new `<item>` block** immediately after `<channel>` opening tag

#### Complete Example

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Contextify Updates</title>
    <link>https://contextify.sh/appcast.xml</link>
    <description>Most recent updates for Contextify</description>
    <language>en</language>

    <!-- NEWEST VERSION FIRST -->
    <item>
      <title>Version 1.1.0</title>
      <pubDate>Thu, 28 Nov 2025 14:30:00 -0800</pubDate>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>
        https://contextify.sh/release-notes/1.1.0.html
      </sparkle:releaseNotesLink>
      <enclosure
        url="https://contextify.sh/releases/Contextify-1.1.0.dmg"
        sparkle:edSignature="ACTUAL_SIGNATURE_FROM_SIGN_SH"
        length="16320758"
        type="application/octet-stream"
        sparkle:os="macos"
      />
    </item>

    <!-- Previous version (keep for rollback) -->
    <item>
      <title>Version 1.0.0</title>
      <!-- ... -->
    </item>
  </channel>
</rss>
```

#### Field Reference

| Field | Value | Notes |
|-------|-------|-------|
| `title` | `Version X.Y.Z` | User-visible in update dialog |
| `pubDate` | RFC 2822 format | `date "+%a, %d %b %Y %H:%M:%S %z"` |
| `sparkle:version` | Integer (1, 2, 3...) | Build number for comparison |
| `sparkle:shortVersionString` | `X.Y.Z` | Marketing version |
| `sparkle:minimumSystemVersion` | `26.0` | macOS Tahoe minimum |
| `sparkle:edSignature` | From sign.sh | EdDSA signature |
| `length` | From sign.sh | File size in bytes |
| `url` | Full URL to DMG | Must be HTTPS |

### 4. Create Release Notes

Release notes are generated during Phase 5 (Marketing) of the release workflow:

1. **Generate LLM draft:** `./scripts/release/generate-release-notes.sh X.Y.Z`
2. **Review and edit:** `releases/vX.Y.Z/assets/changelog.llm.md`
3. **Save final:** `releases/vX.Y.Z/assets/changelog.final.md`
4. **Convert to HTML:** `website/release-notes/X.Y.Z.html`

The HTML file is referenced in the appcast via `<sparkle:releaseNotesLink>`.

#### Dark Mode Support

Sparkle's update dialog displays release notes in a web view that respects the system appearance. **Release notes HTML must include dark mode styles** or text will be unreadable.

Required CSS pattern:

```css
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    color: #333;
    background: #fff;
  }
  h2 { color: #555; }

  @media (prefers-color-scheme: dark) {
    body { background: #1e1e1e; color: #e0e0e0; }
    h2 { color: #aaa; }
  }
</style>
```

Key points:
- Set explicit `background` on body (don't rely on browser default)
- Use `@media (prefers-color-scheme: dark)` for dark mode overrides
- Test in both light and dark mode before deploying

### 5. Deploy

```bash
# Upload DMG
scp dist/Contextify-X.Y.Z.dmg web@banagale.com:/var/www/contextify.sh/releases/

# Upload appcast
scp website/appcast.xml web@banagale.com:/var/www/contextify.sh/

# Upload release notes
scp website/release-notes/X.Y.Z.html web@banagale.com:/var/www/contextify.sh/release-notes/
```

### 6. Verify

```bash
curl -s https://contextify.sh/appcast.xml | head -30
```

## Version Synchronization

**Critical:** App Store and DMG versions must stay in sync.

| Component | Where Version Lives |
|-----------|---------------------|
| Xcode project | `MARKETING_VERSION` in project.pbxproj |
| App Store | App Store Connect (from archive) |
| DMG | Embedded in app bundle |
| Appcast | `sparkle:shortVersionString` |
| GitHub Release | Tag `vX.Y.Z` |
| Website download | `website/macos-version` |
| Install script | Fetches `https://contextify.sh/macos-version` |

### `website/macos-version`

This file contains the bare version number of the latest macOS DMG (e.g., `1.2.0`). It is the source of truth for:
- The website download button (`/go/dmg/` redirect page)
- The `curl|sh` installer on macOS (`detect_macos_version()`)

**This file MUST be updated every time a new DMG is uploaded to GitHub.**

It exists because GitHub's `releases/latest` pointer may point to a Linux-only release, so macOS needs its own version pointer.

### Consistency Check

Run after any release or before website deploy:
```bash
./scripts/release/check-dmg-consistency.sh
```

This verifies `macos-version`, `appcast.xml`, and the GitHub DMG asset are all in sync. Use `--strict` to treat appcast lag as an error.

### Audit Checklist

Before release, verify all match:
```bash
# Xcode version
grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1

# Latest git tag
git tag -l "v*" --sort=-v:refname | head -1

# Appcast version
curl -s https://contextify.sh/appcast.xml | grep shortVersionString | head -1

# GitHub release
gh release list --limit 1
```

## Rollback

If bad release shipped:

1. SSH to server
2. Edit appcast.xml - remove bad version or reorder
3. Previous DMGs remain on server
4. Users get previous version on next check

**Keep 2+ previous DMGs on server.**

## Troubleshooting

### "SUFeedURL not found"
Sparkle keys missing from Info.plist used by build.

### Update check fails silently
Check Console.app for Sparkle logs: `subsystem:org.sparkle-project`

### Signature verification failed
Re-sign DMG with correct private key, update appcast.

## Future: Automation

`scripts/release/release.py` should be extended to:
1. Auto-sign DMG with Sparkle EdDSA
2. Auto-update appcast.xml
3. Auto-deploy to contextify.sh

Until then, steps 2-5 are manual.
