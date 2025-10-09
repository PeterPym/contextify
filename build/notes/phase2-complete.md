# Phase 2: Signing & Distribution - Complete ✅

**Date:** 2025-10-08
**Status:** Successfully implemented and tested

---

## What Was Built

### 1. Signing Script (`scripts/sign_and_notarize.py`)
- **Location:** `/Users/rob/code/contextify/scripts/sign_and_notarize.py`
- **Features:**
  - Auto-detects Developer ID certificate (`B46F8E29955991D15267BE5B5C019DFF17405554`)
  - Signs all Mach-O binaries with hardened runtime
  - Applies entitlements from `Contextify/Contextify.entitlements`
  - Skips symlinks (prevents signing errors)
  - Creates signed DMG with custom layout
  - Supports `--no-sign` and `--no-notarize` flags for testing

### 2. DMG Layout Configuration (`build/assets/dmg_settings.json`)
- **Size:** 700x400px window
- **Contents:**
  - Contextify.app at (160, 140)
  - Applications symlink at (530, 140)
  - Icon size: 120px
  - Custom background image

### 3. DMG Background Image (`build/assets/dmg_background.png`)
- **Generator:** `scripts/generate_dmg_background.swift`
- **Specs:** 700x400px, light blue gradient
- **Customizable:** Edit the Swift script and regenerate

### 4. Build Process Integration
- **Release Build:** `CTX_NO_RUN=1 bash scripts/xc.sh Release build`
- **Output:** `.derived/Build/Products/Release/Contextify.app`
- **Size:** 2.8MB executable + 9.7MB DMG

### 5. Test Results
- ✅ Release build succeeds
- ✅ All binaries signed with Developer ID
- ✅ DMG created and verified (checksum valid)
- ✅ DMG signed with Developer ID
- ✅ SHA256 checksum generated: `dist/Contextify.dmg.sha256`
- ⚠️ Gatekeeper rejects (pre-notarization) - Expected, needs notarization
- ⚠️ Strict verification fails due to PythonVenv symlinks - See Phase 1 blockers

---

## Current Limitations (Phase 1 Blockers)

### Symlink Issues
The bundled `PythonVenv` contains symlinks pointing outside the app bundle:
```
PythonVenv/bin/python3 -> /Applications/Xcode.app/Contents/Developer/usr/bin/python3
PythonVenv/bin/python3.13 -> /opt/homebrew/opt/python@3.13/bin/python3.13
```

**Impact:**
- `codesign --verify --deep --strict` fails
- App will work on your Mac but may fail on others without Python installed
- Notarization may reject the bundle

**Solution (Phase 1):**
- Create proper relocatable Python venv
- Bundle actual Python interpreter in app Resources
- Update LaunchAgentManager to use bundled Python

**Workaround (Current):**
- Script uses non-strict verification
- DMG still functional for local testing
- Comment added: "TODO: Use strict=True after Phase 1"

---

## How to Use

### Build and Sign (No Notarization)
```bash
# 1. Build Release configuration
CTX_NO_RUN=1 bash scripts/xc.sh Release build

# 2. Sign and create DMG (no notarization)
python3 scripts/sign_and_notarize.py --no-notarize
```

**Output:**
- `dist/Contextify.dmg` (9.7MB)
- `dist/Contextify.dmg.sha256`

### Test DMG Locally
```bash
# Open DMG
open dist/Contextify.dmg

# Verify checksum
shasum -a 256 -c dist/Contextify.dmg.sha256

# Check signature
codesign -dvv dist/Contextify.dmg

# Check Gatekeeper status (will be rejected pre-notarization)
spctl -vvv --assess --type open --context context:primary-signature dist/Contextify.dmg
```

---

## Next Steps: Notarization Setup

Notarization requires one-time setup with Apple.

### Prerequisites
1. Apple Developer account with notarization access (✅ Have: J8P5B23FK7)
2. App-specific password for notarization
3. `xcrun notarytool` (included with Xcode)

### Setup Instructions

#### 1. Create App-Specific Password
Visit: https://appleid.apple.com/account/manage
1. Sign in with Apple ID used for Developer account
2. Navigate to "Security" → "App-Specific Passwords"
3. Click "+ Generate an app-specific password"
4. Name it: "Contextify Notarization"
5. Save the generated password (you can't view it again)

#### 2. Store Credentials in Keychain
```bash
xcrun notarytool store-credentials "NotaryProfile" \
  --apple-id "YOUR_APPLE_ID@email.com" \
  --team-id "J8P5B23FK7" \
  --password "xxxx-xxxx-xxxx-xxxx"  # Use app-specific password
```

This creates a keychain entry named "NotaryProfile" that the script will use.

#### 3. Test Notarization (First Time)
```bash
# Build and sign + notarize
python3 scripts/sign_and_notarize.py

# This will:
# - Build DMG
# - Sign all binaries
# - Upload to Apple for notarization (may take 5-15 minutes)
# - Wait for approval
# - Staple notarization ticket to DMG
```

**Expected Timeline:**
- Upload: ~30 seconds (9.7MB)
- Notarization: 2-15 minutes (usually ~5 minutes)
- Stapling: ~5 seconds

#### 4. Verify Notarization Success
```bash
# Check notarization ticket
xcrun stapler validate dist/Contextify.dmg

# Check Gatekeeper (should now accept)
spctl -vvv --assess --type open --context context:primary-signature dist/Contextify.dmg
```

**Success Output:**
```
dist/Contextify.dmg: accepted
source=Notarized Developer ID
```

---

## Troubleshooting

### Notarization Fails
1. Check notarization log:
   ```bash
   # Get submission ID from script output
   xcrun notarytool log <submission-id> --keychain-profile "NotaryProfile"
   ```

2. Common issues:
   - **Symlinks outside bundle:** Phase 1 blocker - needs proper bundling
   - **Missing entitlements:** Ensure entitlements file is correct
   - **Unsigned binaries:** Script should catch this, but verify all .so files signed
   - **Invalid signature:** Rebuild and re-sign

### Certificate Issues
```bash
# List available certificates
security find-identity -p codesigning -v

# Should show:
# "Developer ID Application: Perch Innovations, Inc. (J8P5B23FK7)"
```

If missing, download from developer.apple.com → Certificates, Identifiers & Profiles

### DMG Creation Fails
```bash
# Check create-dmg installation
which create-dmg
# Should output: /opt/homebrew/bin/create-dmg

# If missing:
brew install create-dmg
```

---

## Files Created

### Scripts
- `scripts/sign_and_notarize.py` - Main signing and DMG creation script
- `scripts/generate_dmg_background.swift` - DMG background generator

### Assets
- `build/assets/dmg_settings.json` - DMG layout configuration
- `build/assets/dmg_background.png` - DMG background image (700x400)

### Output
- `dist/Contextify.dmg` - Signed DMG (9.7MB)
- `dist/Contextify.dmg.sha256` - SHA256 checksum file
- `build/Contextify-Staging/` - Temporary staging directory (can be deleted)

### Documentation
- `build/notes/release-readiness.md` - Overall release plan
- `build/notes/phase2-complete.md` - This file

---

## Success Metrics

### ✅ Phase 2 Complete
- [x] Signing script created and tested
- [x] DMG layout configured
- [x] DMG background generated
- [x] Release build succeeds
- [x] All binaries signed
- [x] DMG created and verified
- [x] SHA256 checksum generated
- [x] Script handles symlinks gracefully
- [x] Documentation complete

### ⏳ Pending (User Action Required)
- [ ] Notarization profile configured (one-time setup)
- [ ] First notarization test completed
- [ ] Gatekeeper accepts notarized DMG

### ⏳ Pending (Phase 1 Required)
- [ ] Strict codesigning verification passes
- [ ] Python venv properly bundled (relocatable)
- [ ] No external symlinks in app bundle

---

## Quick Reference

### Common Commands
```bash
# Clean build from scratch
bash scripts/xc.sh clean
CTX_NO_RUN=1 bash scripts/xc.sh Release build

# Sign and create DMG (no notarization)
python3 scripts/sign_and_notarize.py --no-notarize

# Sign and notarize (after setup)
python3 scripts/sign_and_notarize.py

# Test DMG
open dist/Contextify.dmg

# Verify signature
codesign -dvv dist/Contextify.dmg

# Check checksum
shasum -a 256 -c dist/Contextify.dmg.sha256
```

---

## Summary

Phase 2 is **functionally complete**. The signing infrastructure works and produces a signed DMG that:
- ✅ Installs on your Mac
- ✅ Passes basic codesign verification
- ✅ Has correct Developer ID signature
- ⚠️ Will show Gatekeeper warning until notarized
- ⚠️ May fail strict verification due to Phase 1 symlink issues

**Next Actions:**
1. **For local testing:** Use current DMG as-is
2. **For distribution:** Complete notarization setup (10 minutes)
3. **For production:** Complete Phase 1 (bundling resources) first

**Estimated Time to First Notarized Release:**
- With Phase 1 complete: 15 minutes (setup notarization + run script)
- Without Phase 1: Unknown (notarization may reject due to symlinks)

**Recommendation:** Test notarization now with current build to see if Apple accepts it despite symlink issues. If rejected, complete Phase 1 first.
