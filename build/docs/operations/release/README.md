# Release Operations

## Distribution Channels

| Channel | Update Mechanism | Target Users |
|---------|------------------|--------------|
| **App Store** | Apple automatic updates | General users |
| **DMG (Direct)** | Sparkle auto-updates | Power users, beta testers |
| **GitHub Releases** | Manual download | Developers |

## Release Artifacts

Each release produces:

```
dist/
├── Contextify-X.Y.Z.dmg      # Signed, notarized DMG
├── Contextify-X.Y.Z.dmg.sha256
└── (archive for App Store)

website/
├── appcast.xml               # Sparkle update feed
└── release-notes/X.Y.Z.html  # Per-version notes
```

## Version Sources of Truth

| Source | Location | Updated By |
|--------|----------|------------|
| Xcode project | `MARKETING_VERSION` in project.pbxproj | release.py |
| Git tags | `vX.Y.Z` | release.py |
| Appcast | `website/appcast.xml` | Manual (TODO: automate) |
| App Store | App Store Connect | Upload via xc.sh |

## Quick Reference

```bash
# Full automated release (DMG + GitHub)
python3 scripts/release.py --version X.Y.Z --yes

# App Store submission
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload

# Sign DMG for Sparkle (after release.py)
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg
```

## Documentation Index

| Document | Purpose |
|----------|---------|
| [sparkle-updates.md](sparkle-updates.md) | DMG auto-update system (Sparkle) |
| [notarization-setup.md](notarization-setup.md) | Apple notarization credentials |
| [notarization-success.md](notarization-success.md) | Notarization verification |
| [release-build-verification.md](release-build-verification.md) | Build validation steps |
| [release-readiness.md](release-readiness.md) | Pre-release checklist |
| [../guides/APP-STORE-SUBMISSION.md](../guides/APP-STORE-SUBMISSION.md) | App Store process |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/release.py` | End-to-end release automation |
| `scripts/sign_and_notarize.py` | DMG signing + Apple notarization |
| `scripts/sparkle/keygen.sh` | Sparkle EdDSA key management |
| `scripts/sparkle/sign.sh` | Sign DMG for Sparkle updates |
| `scripts/xc.sh` | Build wrapper (DMG vs App Store) |

## Typical Release Flow

### Patch Release (e.g., 1.0.1)

```bash
# 1. Ensure clean state
git status  # Should be clean
swift test  # Should pass

# 2. Run release script
python3 scripts/release.py --version 1.0.1 --yes
# This: bumps version, tags, builds, signs, notarizes, uploads to GitHub

# 3. Sign for Sparkle
./scripts/sparkle/sign.sh dist/Contextify-1.0.1.dmg

# 4. Update appcast.xml with signature (manual for now)

# 5. Deploy to website
scp dist/Contextify-1.0.1.dmg web@banagale.com:/var/www/contextify.sh/releases/
scp website/appcast.xml web@banagale.com:/var/www/contextify.sh/

# 6. (If App Store) Submit via xc.sh
```

### Coordinated Release (App Store + DMG)

Both must be from **same commit**:

```bash
# 1. Build and submit App Store
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload

# 2. Build DMG (same commit!)
python3 scripts/release.py --version X.Y.Z --yes

# 3. Sparkle signing + deploy (as above)
```

## Automation Status

| Step | Automated | Manual |
|------|-----------|--------|
| Version bump | Yes (release.py) | - |
| Git tag | Yes (release.py) | - |
| Build | Yes (release.py) | - |
| Code sign | Yes (sign_and_notarize.py) | - |
| Notarize | Yes (sign_and_notarize.py) | - |
| GitHub release | Yes (release.py) | - |
| Sparkle sign | No | `sparkle/sign.sh` |
| Appcast update | No | Edit XML |
| Website deploy | No | scp |
| App Store upload | Partial | `xc.sh upload` |

**TODO:** Extend release.py to automate Sparkle signing and appcast updates.
