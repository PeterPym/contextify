# Sparkle Auto-Update Setup

DMG builds use [Sparkle](https://sparkle-project.org/) for auto-updates. App Store builds use Apple's update mechanism.

## Build Configuration

| Build Type | Swift Flag | Info.plist | Auto-Updates |
|------------|------------|------------|--------------|
| DMG | `-DSPARKLE` | Info-DMG.plist | Sparkle |
| App Store | `-DAPPSTORE_BUILD` | Info.plist | Apple |

Build DMG: `bash scripts/xc.sh --dist=dmg build`
Build App Store: `bash scripts/xc.sh --dist=appstore build`

**Note:** Current setup uses single Xcode target. Sparkle framework is linked but code is conditionally compiled. For App Store submission, either:
1. Create separate "Contextify AppStore" target without Sparkle SPM dependency
2. Or use xcconfig to conditionally link Sparkle based on distribution

## Key Management

### Initial Setup (One-Time)

```bash
# Generate EdDSA key pair
./scripts/sparkle/keygen.sh

# Copy the public key to Info-DMG.plist as SUPublicEDKey
```

Private key is stored in macOS Keychain. For CI:

```bash
# Export private key for GitHub Secrets
./scripts/sparkle/keygen.sh export

# Then: base64 -i ~/sparkle_private_key.txt | pbcopy
# Add to GitHub Secrets as SPARKLE_PRIVATE_KEY
```

### Key Locations

| Location | Key Type | Purpose |
|----------|----------|---------|
| macOS Keychain | Private | Local signing |
| GitHub Secrets | Private (base64) | CI signing |
| Info-DMG.plist | Public | Bundled in app |

## Release Workflow

```bash
# 1. Build Release DMG
bash scripts/xc.sh --dist=dmg Release build

# 2. Sign and notarize (creates dist/Contextify.dmg)
make sign-dmg

# 3. Sign for Sparkle
./scripts/sparkle/sign.sh dist/Contextify.dmg
# Output: edSignature="..." length="..."

# 4. Update website/appcast.xml with signature and length

# 5. Upload DMG and appcast to server
scp dist/Contextify-X.Y.Z.dmg web@banagale.com:/var/www/contextify.sh/releases/
scp website/appcast.xml web@banagale.com:/var/www/contextify.sh/

# 6. Verify
curl -s https://contextify.sh/appcast.xml | head -30
```

## Appcast Structure

```xml
<item>
  <title>Version X.Y.Z</title>
  <sparkle:version>N</sparkle:version>           <!-- Build number (monotonic) -->
  <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
  <enclosure
    url="https://contextify.sh/releases/Contextify-X.Y.Z.dmg"
    sparkle:edSignature="BASE64_SIGNATURE"
    length="FILE_SIZE_BYTES"
    type="application/octet-stream"
    sparkle:os="macos"
  />
</item>
```

## Bad Release Recovery

If you ship a broken update:

1. SSH to server: `ssh web@banagale.com`
2. Edit appcast.xml to remove bad version or reorder items
3. Previous DMGs are still on server for rollback
4. Users will get previous version on next check

Keep at least 2 previous DMGs on server.

## Files

| File | Purpose |
|------|---------|
| `Contextify/Info-DMG.plist` | DMG-specific Info.plist with Sparkle keys |
| `Contextify/Contextify/CheckForUpdatesView.swift` | Menu item (compiled only with SPARKLE) |
| `website/appcast.xml` | Update feed |
| `website/release-notes/` | Per-version HTML release notes |
| `scripts/sparkle/keygen.sh` | Generate/export EdDSA keys |
| `scripts/sparkle/sign.sh` | Sign DMG for Sparkle |
