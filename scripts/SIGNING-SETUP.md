# Code Signing & Notarization Setup Guide

**Status:** 🟡 Certificates exist, need to install and configure

## Current State

### ✅ Certificates Available (Apple Developer Portal)

You have two Developer ID Application certificates:

1. **Developer ID Application** (expires 2029/05/11)
   - Created by: Robert Banagale
   - Platform: macOS
   - Team: Perch Innovations, Inc.

2. **Developer ID Application** (expires 2030/06/11)
   - Created by: Robert Banagale
   - Platform: macOS
   - Team: Perch Innovations, Inc.

**Recommendation:** Use the newer one (expires 2030/06/11) for longest validity.

### ❌ Local Setup Needed

- [ ] Certificate installed in Keychain
- [ ] Notarization credentials configured

## Setup Steps

### Step 1: Download & Install Developer ID Certificate

1. **Go to Apple Developer Portal:**
   - Visit: https://developer.apple.com/account/resources/certificates/list
   - Find: "Developer ID Application" (expires 2030/06/11)

2. **Download Certificate:**
   - Click on the certificate
   - Click "Download" button
   - Save file (will be named something like `developerID_application.cer`)

3. **Install in Keychain:**
   ```bash
   # Double-click the downloaded .cer file, OR:
   open ~/Downloads/developerID_application.cer
   ```
   - This will open Keychain Access
   - Certificate will be added to "login" keychain
   - Verify it appears under "My Certificates"

4. **Verify Installation:**
   ```bash
   security find-identity -p codesigning -v | grep "Developer ID Application"
   ```

   **Expected output:**
   ```
   1) XXXXXXXXXXXX "Developer ID Application: Perch Innovations, Inc. (J8P5B23FK7)"
   ```

### Step 2: Create App-Specific Password

Apple requires an app-specific password for notarization (not your Apple ID password).

1. **Generate Password:**
   - Visit: https://appleid.apple.com/account/manage
   - Sign in with rob@banagale.com
   - Under "Security" → "App-Specific Passwords"
   - Click "+" to generate new password
   - Name it: "Contextify Notarization"
   - **Copy the password** (format: xxxx-xxxx-xxxx-xxxx)

### Step 3: Store Notarization Credentials

```bash
# Store credentials in keychain as "NotaryProfile"
xcrun notarytool store-credentials NotaryProfile \
  --apple-id rob@banagale.com \
  --team-id J8P5B23FK7 \
  --password <paste-app-specific-password-here>
```

**Enter the password when prompted** (the xxxx-xxxx-xxxx-xxxx from Step 2)

**Verify it worked:**
```bash
xcrun notarytool history --keychain-profile NotaryProfile
```

Should show recent notarization history (or "No submissions found" if first time).

### Step 4: Test Signing

```bash
# Build Release
make build-release

# Test signing (without notarization for speed)
python3 scripts/sign_and_notarize.py --no-notarize
```

**Expected output:**
```
🚀 Contextify Sign & Notarize
📂 Project root: /Users/rob/code/projects/contextify
🔑 Certificate: XXXXXXXXXXXX
...
🔏 Signing N binaries...
✅ Verifying signature: Contextify.app
📀 Creating DMG: Contextify.dmg
✅ DMG built & signed (notarization skipped).
📦 dist/Contextify.dmg
```

### Step 5: Test Full Workflow (Dry Run)

```bash
# Preview what a release would do
python3 scripts/release.py --version 1.0.0 --dry-run --yes
```

Should complete without errors and show:
```
(dry-run) Would perform:
  1. Bump Xcode version to 1.0.0
  2. Create and push tag v1.0.0
  3. Build Release configuration
  4. Sign and notarize DMG
  5. Upload to GitHub
```

## Verification Checklist

Run these commands to verify setup:

```bash
# 1. Check Developer ID certificate exists
security find-identity -p codesigning -v | grep "Developer ID Application"
# ✅ Should show certificate hash and "Developer ID Application: Perch Innovations, Inc."

# 2. Check notarization credentials exist
xcrun notarytool history --keychain-profile NotaryProfile 2>&1 | head -3
# ✅ Should NOT show "Error: No Keychain password item found"

# 3. Check gh CLI is authenticated
gh auth status
# ✅ Should show "Logged in to github.com as banagale"

# 4. Check create-dmg is installed
which create-dmg
# ✅ Should show path like /opt/homebrew/bin/create-dmg

# 5. Test release script can read version
python3 scripts/release.py --version 1.0.0 --dry-run --yes
# ✅ Should complete without errors
```

## Troubleshooting

### "✖ Developer-ID certificate not found"

**Problem:** Certificate not installed or not visible to `security` command

**Solution:**
1. Open Keychain Access
2. Select "login" keychain
3. Category: "My Certificates"
4. Look for "Developer ID Application: Perch Innovations, Inc."
5. If not there, repeat Step 1 (download & install)

### "Error: No Keychain password item found for profile: NotaryProfile"

**Problem:** Notarization credentials not configured

**Solution:** Repeat Step 2 and Step 3 above

### "Password incorrect" when storing credentials

**Problem:** Using Apple ID password instead of app-specific password

**Solution:**
1. Generate new app-specific password (Step 2)
2. Use that password (format: xxxx-xxxx-xxxx-xxxx), not your Apple ID password

### Multiple certificates showing up

**Problem:** Both certificates (2029 and 2030) installed

**Solution:** This is fine! The script will auto-detect and use the first valid one. If you want to be specific, you can remove the older one from Keychain Access.

## Security Notes

- App-specific password is stored in macOS Keychain (encrypted)
- NotaryProfile can be used indefinitely (no need to re-enter password)
- If you regenerate the app-specific password in Apple ID, you must re-run Step 3
- Certificates are tied to your Apple Developer account (requires active membership)

## Next Steps

Once setup is complete:

1. **Test build & sign:**
   ```bash
   make build-release
   make sign-dmg-no-notarize
   ```

2. **Test full notarization:**
   ```bash
   make build-release
   make sign-dmg  # Takes ~4-7 minutes for Apple to notarize
   ```

3. **Create first release:**
   ```bash
   python3 scripts/release.py --version 1.0.0 --yes
   ```

---

**Setup Time:** ~10-15 minutes
**One-time setup:** Yes (credentials persist in Keychain)
**Last Updated:** 2025-11-01
