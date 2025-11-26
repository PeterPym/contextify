# Sparkle Scripts

Scripts for DMG auto-update signing.

**Full documentation:** `build/docs/operations/release/sparkle-updates.md`

## Scripts

| Script | Purpose |
|--------|---------|
| `keygen.sh` | Generate/export EdDSA keys |
| `sign.sh` | Sign DMG for Sparkle verification |

## Quick Usage

```bash
# Sign a DMG (outputs signature for appcast.xml)
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg

# Generate new keys (one-time setup)
./scripts/sparkle/keygen.sh

# Export private key for CI
./scripts/sparkle/keygen.sh export
```
