# macOS App Store Submission Guide

Step-by-step guide for submitting a macOS app to the App Store, based on the Contextify submission process (November 2025).

## Prerequisites

### Apple Developer Account
- Enrolled in Apple Developer Program ($99/year)
- Account with Admin or Account Holder role
- Team ID (found in Membership details)

### Required Certificates (create at developer.apple.com/account/resources/certificates)
1. **Apple Distribution** - Signs the .app bundle
2. **Mac Installer Distribution** - Signs the .pkg installer

### Certificate Signing Request (CSR)
Create once via Keychain Access:
1. Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority
2. Enter email, select "Saved to disk"
3. Save the `.certSigningRequest` file (reuse for all certs)

Store CSR somewhere permanent: `/Users/yourname/code/certificates/CertificateSigningRequest.certSigningRequest`

---

## One-Time Setup

### 1. Create App Store Connect API Key
1. Go to https://appstoreconnect.apple.com → Users and Access → Integrations → Keys
2. Click **+** to generate a new key
3. Name it (e.g., "CLI Upload")
4. Select **Admin** or **App Manager** role
5. Download the `.p8` file (only available once!)
6. Note the **Key ID** and **Issuer ID**

Store the key:
```bash
mkdir -p ~/.private_keys
cp ~/Downloads/AuthKey_XXXXXXXX.p8 ~/.private_keys/
```

### 2. Create Certificates

#### Apple Distribution Certificate
1. https://developer.apple.com/account/resources/certificates/list
2. Click **+** → **Apple Distribution**
3. Upload your CSR
4. Download and double-click to install

#### Mac Installer Distribution Certificate
1. Same page, click **+** → **Mac Installer Distribution**
2. Upload your CSR
3. Download and double-click to install

Verify installed:
```bash
security find-identity -v -p codesigning | grep -i "distribution\|installer"
```

Should show:
```
"Apple Distribution: Your Name (TEAMID)"
"3rd Party Mac Developer Installer: Your Name (TEAMID)"
```

### 3. Register App ID
1. https://developer.apple.com/account/resources/identifiers/list
2. Click **+** → **App IDs** → **App**
3. Select **Mac** platform
4. Enter Bundle ID (e.g., `sh.contextify.Contextify`) - use reverse domain notation
5. Add description
6. Enable any capabilities needed (usually none for basic apps)
7. Click Register

### 4. Create Provisioning Profile
1. https://developer.apple.com/account/resources/profiles/list
2. Click **+** → **Mac App Store Connect**
3. Select **Mac** (not Mac Catalyst)
4. Select your App ID
5. Select your Apple Distribution certificate
6. Name it (e.g., "AppName Mac App Store")
7. Download

Install the profile:
```bash
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp ~/Downloads/YourProfile.provisionprofile ~/Library/MobileDevice/Provisioning\ Profiles/
```

Note: Production profiles cannot be installed via double-click - must copy manually.

### 5. Create App in App Store Connect
1. https://appstoreconnect.apple.com → My Apps → **+** → New App
2. Select **macOS**
3. Enter name, primary language, Bundle ID, SKU
4. SKU can be anything (internal reference, cannot be changed later)

---

## Required Info.plist Keys

Add these to your Info.plist before archiving:

```xml
<!-- App category (required) -->
<key>LSApplicationCategoryType</key>
<string>public.app-category.developer-tools</string>

<!-- Skip encryption export compliance question -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>

<!-- Copyright -->
<key>NSHumanReadableCopyright</key>
<string>Copyright © 2025 YourCompany. All rights reserved.</string>
```

Common category values:
- `public.app-category.developer-tools`
- `public.app-category.productivity`
- `public.app-category.utilities`
- `public.app-category.business`

---

## Export Options Plist

Create `ExportOptions-AppStore.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Apple Distribution</string>
    <key>installerSigningCertificate</key>
    <string>3rd Party Mac Developer Installer</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>your.bundle.id</key>
        <string>Your Profile Name</string>
    </dict>
</dict>
</plist>
```

---

## Build & Upload Commands

### Archive
```bash
xcodebuild archive \
  -project YourApp.xcodeproj \
  -scheme YourApp \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath build/YourApp.xcarchive
```

### Export as .pkg
```bash
xcodebuild -exportArchive \
  -archivePath build/YourApp.xcarchive \
  -exportPath build/appstore \
  -exportOptionsPlist ExportOptions-AppStore.plist
```

### Upload to App Store Connect
```bash
xcrun altool --upload-app \
  --type macos \
  --file build/appstore/YourApp.pkg \
  --apiKey YOUR_KEY_ID \
  --apiIssuer YOUR_ISSUER_ID
```

---

## Troubleshooting

### "No profiles for 'bundle.id' were found"
- Provisioning profile not installed or wrong bundle ID
- Copy profile to `~/Library/MobileDevice/Provisioning Profiles/`
- Verify bundle ID matches exactly

### "Provisioning profile doesn't include signing certificate"
- Profile was created with a different certificate than installed
- Delete and recreate the provisioning profile
- Make sure only one Apple Distribution cert exists (delete duplicates from Keychain)

### "No signing certificate 'Mac Installer Distribution' found"
- Create the Mac Installer Distribution certificate (separate from Apple Distribution)
- Download and install it

### "LSApplicationCategoryType key" error
- Add `LSApplicationCategoryType` to Info.plist

### "Cannot determine Apple ID from Bundle ID"
- Bundle ID in App Store Connect doesn't match the built app
- Update bundle ID in App Store Connect → App Information

### Duplicate certificates
Check for duplicates:
```bash
security find-certificate -a -c "Apple Distribution" -Z | grep "SHA-1"
```

Remove duplicates in Keychain Access, keeping only one.

---

## Post-Upload

1. Wait 5-15 minutes for Apple to process the build
2. Check status at: https://appstoreconnect.apple.com/apps/YOUR_APP_ID/testflight/macos
3. Once processed, go to App Store tab → macOS App → select the version
4. **Export Compliance**: You'll be asked about encryption:
   - "What type of encryption algorithms does your app implement?"
   - Select **"None of the algorithms mentioned above"** (if you don't use custom crypto)
   - This is required before you can select the build
5. **Select Build**: Click the **+** next to "Build" and select your uploaded build
6. Complete App Store listing (screenshots, description, keywords, etc.)

---

## Required Before Submission

Complete these sections in App Store Connect before you can submit for review:

### App Information Tab
- **Content Rights**: Confirm you own or have rights to all content in the app
- **Primary Category**: Select appropriate category (e.g., Developer Tools)
- **Secondary Category** (optional): Select if applicable

### Pricing and Availability Tab
- **Price**: Select price tier (e.g., Free, or a paid tier)
- **Availability**: Select countries/regions

### App Privacy Tab
- **Privacy Policy URL**: Required - must be a publicly accessible URL (e.g., `https://yoursite.com/privacy.html`)
- **Data Collection**: Answer questions about what data your app collects
  - If no data collected, select "No, we do not collect data from this app"

### Age Rating
- Answer questionnaire about content (violence, gambling, mature themes, etc.)
- For most developer tools: Answer "None" to all questions → results in 4+ rating

### Version Information (App Store Tab)
- **Screenshots**: Required for each supported screen size
- **Description**: App description (up to 4000 characters)
- **Keywords**: Comma-separated, up to 100 characters total
- **Support URL**: Required
- **Marketing URL** (optional)
- **What's New**: Release notes for this version
- **Review Notes** (optional but recommended): Instructions for Apple reviewers

---

## App Review Materials (Guideline 2.1)

Apps that access external data or require specific setup may need additional materials for Apple to review.

### When Required

- First submission of apps accessing external files
- After rejection requesting sample data or demo video
- When Apple explicitly requests materials

### Materials for Contextify

| Material | Purpose | Location |
|----------|---------|----------|
| Sample Data | Test transcript summarization | `appstore-metadata/review-materials/sample-data.zip` |
| Demo Video | Show all features on physical Mac | Record following script |
| Review Notes | Setup instructions for Apple | `appstore-metadata/fastlane/metadata/review_information/notes.txt` |

### Hosted URLs (Obscured)

```
https://contextify.sh/review-4a125b1d/sample-data.zip
https://contextify.sh/review-4a125b1d/demo-video.mp4
```

### Workflow

1. **Build App Store archive** (will use for both demo and submission):
   ```bash
   bash scripts/xc.sh --dist=appstore Release archive
   ```

2. **Record demo video** using archived binary:
   ```bash
   # Run the archived app
   open build/Contextify.xcarchive/Products/Applications/Contextify.app
   # Record following: appstore-metadata/review-materials/DEMO-VIDEO-SCRIPT.md
   ```

3. **Save demo video**:
   ```bash
   cp ~/path/to/recorded-video.mp4 website/review-4a125b1d/demo-video.mp4
   ```

4. **Deploy to website**:
   ```bash
   ./scripts/deploy-website.sh
   ```

5. **Upload same archive to App Store**:
   ```bash
   bash scripts/xc.sh export-pkg
   bash scripts/xc.sh upload
   ```

6. **Add review notes** to App Store Connect → App Review Information → Notes:
   ```bash
   cat appstore-metadata/fastlane/metadata/review_information/notes.txt
   ```

**Full workflow:** See `build/docs/operations/release/RELEASE-CHECKLIST.md` → "App Store Review Materials"

---

## Submit for Review

Once all required sections are complete:
1. Click **Add for Review** button
2. Answer any final compliance questions
3. Click **Submit to App Review**
4. Wait for review (typically 1-7 days for macOS apps)

### Avoiding Export Compliance Question on Future Uploads

Add this to Info.plist to skip the question:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

---

## Quick Reference Commands

```bash
# Check installed signing identities
security find-identity -v -p codesigning

# List apps in App Store Connect
xcrun altool --list-apps --apiKey KEY_ID --apiIssuer ISSUER_ID

# Validate without uploading
xcrun altool --validate-app --file build/appstore/App.pkg --apiKey KEY_ID --apiIssuer ISSUER_ID
```

---

## Files to Keep Outside Repo

- `.p8` API key files → `~/.private_keys/`
- `.cer` certificate files → `/Users/yourname/code/certificates/`
- `.certSigningRequest` → `/Users/yourname/code/certificates/`
- `.provisionprofile` → `~/Library/MobileDevice/Provisioning Profiles/`

Add to `.gitignore`:
```
.secrets/
build/appstore/
build/*.xcarchive/
```

---

## Contextify-Specific Reference

- **Team ID:** J8P5B23FK7
- **Bundle ID:** sh.contextify.Contextify
- **App Store Connect:** https://appstoreconnect.apple.com/apps/6753190666
- **API Key ID:** AG868N57U6
- **Issuer ID:** 69a6de89-2083-47e3-e053-5b8c7c11a4d1

Build commands:
```bash
# Full App Store flow
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
```

### Two-Target Architecture

Contextify uses **two separate Xcode targets** to support both distribution channels:

| Target | Scheme | Distribution | Sparkle | Sandbox |
|--------|--------|--------------|---------|---------|
| **Contextify** | Contextify | DMG (GitHub) | ✓ Included | No |
| **Contextify AppStore** | Contextify AppStore | App Store | ✗ Excluded | Yes |

**Why separate targets?**
- Apple rejects App Store builds containing Sparkle.framework (unsandboxed executables)
- DMG builds need Sparkle for auto-updates
- Separate targets with different `packageProductDependencies` cleanly solve this

**Swift compilation flags:**
- `SPARKLE` - Defined for DMG target, enables Sparkle code paths
- `APPSTORE_BUILD` - Defined for App Store target, disables Sparkle code paths

The `--dist=appstore` flag automatically selects the correct target/scheme.

---

## Submitting a New Version

When releasing an update to an existing app:

### 1. Build and Upload

```bash
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
```

### 2. Create New Version in App Store Connect

1. Navigate to: App Store → macOS App
2. Click **+ Version** (or select existing draft)
3. Enter version number (must match `MARKETING_VERSION` in Xcode)

### 3. Required Updates

| Field | When to Update |
|-------|----------------|
| **What's New** | Every version (required) |
| **Build** | Every version (select uploaded build) |
| **Screenshots** | If UI changed significantly |
| **Description** | If features changed |
| **Keywords** | If targeting new search terms |

### 4. Submit

1. Select the new build
2. Update "What's New in This Version"
3. Click **Add for Review**
4. Submit to App Review

---

## Handling Rejections

### Finding Rejection Details

1. App Store Connect → Your App
2. Click **Activity** tab
3. Select the rejected build
4. Click **Resolution Center**

### Common Rejections and Fixes

| Guideline | Issue | Fix |
|-----------|-------|-----|
| **2.1** | App crashes/incomplete | Fix code, rebuild, re-upload |
| **2.3** | Inaccurate metadata | Update description/screenshots |
| **4.2** | Minimum functionality | Add features or appeal |
| **5.1.1** | Privacy policy issue | Update privacy policy URL |
| **5.1.2** | Data collection undisclosed | Update App Privacy section |

### Response Workflow

**Metadata-only fix:**
1. Make changes in App Store Connect
2. Resubmit same build

**Code fix required:**
```bash
# Fix the code
# Commit changes

# Rebuild and upload (same version number is OK)
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload

# In App Store Connect:
# - Select new build
# - Resubmit for review
```

**Appealing a rejection:**
1. Go to Resolution Center
2. Click **Reply**
3. Be professional, specific, and reference guidelines
4. Provide evidence (screenshots, documentation) if applicable
5. Submit appeal

### Tips for Avoiding Rejections

- Test on clean macOS install before submission
- Ensure all entitlements are justified
- Privacy policy must be accessible and accurate
- Screenshots must reflect actual app UI
- Description must accurately describe features

---

## Version Backdating

**Scenario:** Development has progressed past the submitted version (e.g., code is at "1.1.0" level) but you want to release as the pending version (e.g., "1.0.0").

**When valid:**
- App Store submission is pending (not yet approved)
- DMG has NOT been released publicly
- Git tag for higher version has NOT been pushed

### Procedure

1. **Update Xcode version:**
   ```bash
   # Edit MARKETING_VERSION in project.pbxproj to target version
   # Or use release.py which handles this
   ```

2. **Clean up git tags:**
   ```bash
   # Delete higher version tag if it exists
   git tag -d v1.1.0
   git push origin --delete v1.1.0  # if pushed
   ```

3. **Create correct tag and rebuild:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0

   # Rebuild App Store
   bash scripts/xc.sh --dist=appstore Release archive
   bash scripts/xc.sh export-pkg
   bash scripts/xc.sh upload
   ```

4. **Select new build in App Store Connect**

**Full details:** See `build/docs/operations/release/RELEASE-CHECKLIST.md`
