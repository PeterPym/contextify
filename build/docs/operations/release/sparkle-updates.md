# Sparkle Auto-Updates (DMG Distribution)

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
python3 scripts/release.py --version X.Y.Z --yes
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

Edit `website/appcast.xml`:

```xml
<item>
  <title>Version X.Y.Z</title>
  <pubDate>Mon, 25 Nov 2025 12:00:00 -0800</pubDate>
  <sparkle:version>BUILD_NUMBER</sparkle:version>
  <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
  <sparkle:releaseNotesLink>
    https://contextify.sh/release-notes/X.Y.Z.html
  </sparkle:releaseNotesLink>
  <enclosure
    url="https://contextify.sh/releases/Contextify-X.Y.Z.dmg"
    sparkle:edSignature="PASTE_SIGNATURE_HERE"
    length="PASTE_LENGTH_HERE"
    type="application/octet-stream"
    sparkle:os="macos"
  />
</item>
```

### 4. Create Release Notes

Create `website/release-notes/X.Y.Z.html` with changes.

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

`scripts/release.py` should be extended to:
1. Auto-sign DMG with Sparkle EdDSA
2. Auto-update appcast.xml
3. Auto-deploy to contextify.sh

Until then, steps 2-5 are manual.
