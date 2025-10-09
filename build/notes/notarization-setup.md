# Notarization Setup Guide

**Date:** 2025-10-09
**Status:** Ready to configure notarization credentials

---

## Current Status ✅

### Completed
- ✅ Developer ID certificate found: `B46F8E29955991D15267BE5B5C019DFF17405554`
- ✅ Team ID: `J8P5B23FK7`
- ✅ Signing script tested successfully with `--no-notarize`
- ✅ Signed DMG created: `dist/Contextify.dmg` (9.7MB)
- ✅ Checksum: `19f01bd76bae819edc7288366b527d2d3918805d4b18c910ad8f2800b734622e`

### Remaining
- ⏳ Create app-specific password for notarization
- ⏳ Store credentials in keychain as "NotaryProfile"
- ⏳ Test full notarization workflow
- ⏳ Verify DMG passes Gatekeeper on this Mac

---

## Step 1: Create App-Specific Password (~5 minutes)

You need to create an app-specific password for notarytool to use with your Apple ID.

1. Go to **https://appleid.apple.com**
2. Sign in with your Apple ID
3. Navigate to **Security** → **App-Specific Passwords**
4. Click **"Generate an app-specific password"**
5. Name it: `Contextify Notarization`
6. **Copy the generated password** (format: `xxxx-xxxx-xxxx-xxxx`)

**Important:** Save this password securely - you won't be able to view it again!

---

## Step 2: Store Credentials in Keychain (~2 minutes)

Once you have your app-specific password, run this command to store it securely:

```bash
xcrun notarytool store-credentials "NotaryProfile" \
  --apple-id "YOUR_APPLE_ID@email.com" \
  --team-id "J8P5B23FK7" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

**Replace:**
- `YOUR_APPLE_ID@email.com` with your Apple ID email
- `xxxx-xxxx-xxxx-xxxx` with the app-specific password from Step 1

**What this does:**
- Stores credentials in your login keychain
- Creates a profile named "NotaryProfile" (used by sign_and_notarize.py)
- Credentials are encrypted and secure

---

## Step 3: Test Notarization (~15 minutes)

After storing credentials, run the full signing and notarization workflow:

```bash
python3 scripts/sign_and_notarize.py
```

**Expected output:**
1. Signs all binaries and the app bundle
2. Creates DMG
3. **Submits DMG to Apple for notarization** (5-15 minutes wait)
4. Polls Apple servers for status
5. Staples notarization ticket to DMG
6. Success message: "✅ DMG built, signed, notarized, stapled."

**Timeline:**
- Signing: ~30 seconds
- DMG creation: ~10 seconds
- Apple notarization: **5-15 minutes** (varies)
- Total: ~6-16 minutes

---

## Step 4: Verify Notarization

After notarization completes, verify Gatekeeper accepts the DMG:

```bash
# Check notarization status
spctl -vvv --assess --type install dist/Contextify.dmg

# Expected output: "accepted"
# If rejected: notarization failed or wasn't stapled correctly
```

**Open and test:**
```bash
open dist/Contextify.dmg
# Drag Contextify.app to Applications
# Launch from Applications folder
# Should launch without warnings
```

---

## Troubleshooting

### Issue: "xcrun: error: unable to find utility 'notarytool'"

**Solution:** Update Xcode Command Line Tools
```bash
softwareupdate --list
softwareupdate --install "Command Line Tools for Xcode"
```

### Issue: "Error: Invalid credentials"

**Possible causes:**
1. Wrong Apple ID email
2. Expired or incorrect app-specific password
3. Wrong Team ID

**Solution:** Delete and recreate credentials
```bash
# Delete from keychain
security delete-generic-password -s "NotaryProfile"

# Recreate with correct info
xcrun notarytool store-credentials "NotaryProfile" \
  --apple-id "correct@email.com" \
  --team-id "J8P5B23FK7" \
  --password "new-app-password"
```

### Issue: Notarization rejected by Apple

**Common reasons:**
1. Unsigned or improperly signed binaries
2. Invalid entitlements
3. Hardened runtime issues

**Check logs:**
```bash
xcrun notarytool log <submission-id> --keychain-profile NotaryProfile
```

### Issue: DMG still shows Gatekeeper warnings

**Possible causes:**
1. Notarization ticket not stapled
2. Testing cached version
3. Signature invalidated

**Solution:** Re-staple
```bash
xcrun stapler staple dist/Contextify.dmg
xcrun stapler validate dist/Contextify.dmg
```

---

## After Notarization Succeeds

### Test on Fresh Mac (Recommended)
1. Copy DMG to another Mac (or test VM)
2. Double-click to mount
3. Drag to Applications
4. Launch - should work without warnings

### Create GitHub Release
```bash
# Tag the release
git tag -a v1.0.0 -m "First release"
git push origin v1.0.0

# Create release with DMG
gh release create v1.0.0 dist/Contextify.dmg \
  --title "Contextify v1.0.0" \
  --notes "First stable release"
```

---

## Quick Reference

**Your Info:**
- Team ID: `J8P5B23FK7`
- Certificate Hash: `B46F8E29955991D15267BE5B5C019DFF17405554`
- Keychain Profile: `NotaryProfile`

**Commands:**
```bash
# Sign only (no notarization)
python3 scripts/sign_and_notarize.py --no-notarize

# Full workflow (sign + notarize)
python3 scripts/sign_and_notarize.py

# Check credentials
security find-generic-password -s "NotaryProfile" -w

# Verify DMG signature
codesign -vvv --deep dist/Contextify.dmg

# Check Gatekeeper
spctl -vvv --assess --type install dist/Contextify.dmg
```

---

## Next Steps (After Notarization Works)

1. **Update current.md** - Mark P1 tasks complete
2. **Test daemon with clean venv** - Verify auto-repair works
3. **Document release checklist** - Steps for future releases
4. **Consider automation** - Phase 3 from release-readiness.md

---

**Generated:** 2025-10-09
**Ready for:** User to create app-specific password and configure notarization
