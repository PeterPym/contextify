# Release Checklist

Master checklist for releasing Contextify. Covers both DMG (direct) and App Store distributions.

**Strategy:** DMG leads, App Store follows. Both built from same commit, same version. DMG ships immediately; App Store ships after Apple review (24-48h).

## Quick Reference

```bash
# Initialize or reset release
./scripts/release/init.sh X.Y.Z          # New release
./scripts/release/init.sh X.Y.Z --reset  # Reset for new build

# Build both distributions (recommended)
./scripts/release/build.sh X.Y.Z

# Upload App Store build
bash scripts/xc.sh upload

# Deploy DMG to website
scp dist/Contextify-X.Y.Z.dmg web@banagale.com:/var/www/contextify.sh/releases/
# Update appcast.xml, deploy
```

## Build Scripts

| Script | Purpose | Use When |
|--------|---------|----------|
| `scripts/xc.sh` | Development builds, Xcode operations | Day-to-day development |
| `scripts/build-release.sh` | Standalone release build | Building without tracking |
| `scripts/release/build.sh` | Release workflow build | Building with version tracking |

<details>
<summary>Manual build commands (alternative)</summary>

```bash
# DMG
python3 scripts/release.py --version X.Y.Z --yes
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg

# App Store
bash scripts/xc.sh --dist=appstore Release archive
bash scripts/xc.sh export-pkg
bash scripts/xc.sh upload
```
</details>

---

## Pre-Release Checklist

### Code Quality
- [ ] All P0 blockers resolved: `grep "P0" TODOS.md`
- [ ] Tests pass: `swift test` (expect 79/79)
- [ ] Build clean: `bash scripts/xc.sh build` (zero warnings)
- [ ] Working directory clean: `git status`

### Version Planning
- [ ] Decide version number (semantic versioning: MAJOR.MINOR.PATCH)
- [ ] Check current version: `grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1`
- [ ] Prepare release notes content

---

## DMG Release (Ships Immediately)

### 1. Build and Sign

```bash
# Automated: bumps version, tags, builds, signs, notarizes, uploads to GitHub
python3 scripts/release.py --version X.Y.Z --yes
```

Output: `dist/Contextify-X.Y.Z.dmg` (signed, notarized)

### 2. Sign for Sparkle Auto-Updates

```bash
./scripts/sparkle/sign.sh dist/Contextify-X.Y.Z.dmg
```

Output (save these values):
```
sparkle:edSignature="abc123..."
length="12345678"
```

### 3. Update Appcast

Edit `website/appcast.xml`:

```xml
<!-- Add new item at TOP (newest first) -->
<item>
  <title>Version X.Y.Z</title>
  <pubDate>Thu, 28 Nov 2025 12:00:00 -0800</pubDate>
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

**Date format (RFC 2822):** `Day, DD Mon YYYY HH:MM:SS -0800`
- Generate: `date -R` or `date "+%a, %d %b %Y %H:%M:%S %z"`

**Build number:** Monotonically increasing integer (1, 2, 3...). Check previous in appcast.

### 4. Create Release Notes

Create `website/release-notes/X.Y.Z.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Contextify X.Y.Z Release Notes</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
      line-height: 1.6;
    }
    h1 { font-size: 1.5em; }
    h2 { font-size: 1.2em; color: #555; margin-top: 1.5em; }
    ul { padding-left: 1.5em; }
    li { margin-bottom: 0.5em; }
  </style>
</head>
<body>
  <h1>Contextify X.Y.Z</h1>
  <p>Brief summary of this release.</p>

  <h2>New Features</h2>
  <ul>
    <li>Feature description</li>
  </ul>

  <h2>Improvements</h2>
  <ul>
    <li>Improvement description</li>
  </ul>

  <h2>Bug Fixes</h2>
  <ul>
    <li>Fix description</li>
  </ul>
</body>
</html>
```

### 5. Deploy to Website

```bash
# Upload DMG
scp dist/Contextify-X.Y.Z.dmg web@banagale.com:/var/www/contextify.sh/releases/

# Upload appcast
scp website/appcast.xml web@banagale.com:/var/www/contextify.sh/

# Upload release notes
scp website/release-notes/X.Y.Z.html web@banagale.com:/var/www/contextify.sh/release-notes/
```

### 6. Verify DMG Release

```bash
# Verify appcast is live
curl -s https://contextify.sh/appcast.xml | grep shortVersionString | head -1

# Verify DMG downloads
curl -I https://contextify.sh/releases/Contextify-X.Y.Z.dmg | grep "200 OK"

# Verify release notes
curl -s https://contextify.sh/release-notes/X.Y.Z.html | head -5
```

---

## App Store Release (Ships After Review)

### 1. Build and Upload

```bash
# Archive (uses "Contextify AppStore" target, excludes Sparkle)
bash scripts/xc.sh --dist=appstore Release archive

# Export as .pkg
bash scripts/xc.sh export-pkg

# Upload to App Store Connect
bash scripts/xc.sh upload

# Record submission (after submitting in App Store Connect)
./scripts/release/mark-submitted.sh X.Y.Z --build N
```

### 2. Complete in App Store Connect

1. **Wait for processing** (5-15 minutes)
   - Check: https://appstoreconnect.apple.com/apps/6753190666/testflight/macos

2. **Create/select version**
   - App Store tab → macOS App
   - If new version: click + Version, enter X.Y.Z
   - If updating existing: select the version

3. **Select build**
   - Click + next to "Build"
   - Select the uploaded build

4. **Update "What's New"**
   - Required for every version
   - Can differ from Sparkle release notes (App Store audience may differ)

5. **Review other metadata** (if applicable)
   - Screenshots: Update if UI changed significantly
   - Description: Update if features changed
   - Keywords: Update if targeting new terms

6. **Submit for review**
   - Click "Add for Review"
   - Answer any compliance questions
   - Click "Submit to App Review"

### 3. Post-Submission

- Review typically takes 24-48 hours for macOS
- Monitor status in App Store Connect
- Be available to respond to reviewer questions

---

## App Store Review Materials (Guideline 2.1)

Apple may request additional materials when reviewing apps that access external data or require specific setup. For Contextify, this includes sample transcript files and a demo video.

### When Required

Review materials are required:
- First App Store submission
- After rejection requesting materials (Guideline 2.1)
- When Apple specifically requests them

### Materials Location

```
appstore-metadata/review-materials/
├── README.md                    # Guide to review materials
├── DEMO-VIDEO-SCRIPT.md         # Recording script
├── sample-data.zip              # Sample transcripts for Apple
└── sample-transcripts/          # Raw transcript files (57 files)

website/review-4a125b1d/         # Hosted files (obscure URL)
├── sample-data.zip              # → https://contextify.sh/review-4a125b1d/sample-data.zip
└── demo-video.mp4               # → https://contextify.sh/review-4a125b1d/demo-video.mp4
```

### Recording Demo Video

**Critical:** Record using the EXACT binary you're submitting.

#### 1. Build and Preserve Archive

```bash
# Build App Store archive
bash scripts/xc.sh --dist=appstore Release archive

# Archive is at: build/Contextify.xcarchive
# Preserve it for consistency:
cp -r build/Contextify.xcarchive build/archives/Contextify-X.Y.Z-appstore.xcarchive
```

#### 2. Export and Run for Demo

```bash
# Export the app (not pkg) for local testing
xcodebuild -exportArchive \
  -archivePath build/Contextify.xcarchive \
  -exportPath build/demo-app \
  -exportOptionsPlist ExportOptions-AppStore.plist

# Run the exported app for demo recording
open build/demo-app/Contextify.app
```

**Alternative:** Run directly from archive:
```bash
open build/Contextify.xcarchive/Products/Applications/Contextify.app
```

#### 3. Record Demo Following Script

Follow `appstore-metadata/review-materials/DEMO-VIDEO-SCRIPT.md`:
- Show permission dialogs
- Demonstrate all features
- Use sample transcript data

Save as: `website/review-4a125b1d/demo-video.mp4`

#### 4. Upload Same Archive to App Store

```bash
# Export as .pkg (from same archive)
bash scripts/xc.sh export-pkg

# Upload
bash scripts/xc.sh upload
```

This ensures the demo video shows exactly what Apple will review.

### Updating Review Notes

Copy review notes to App Store Connect → App Review Information → Notes:

```bash
cat appstore-metadata/fastlane/metadata/review_information/notes.txt
```

Or see `appstore-metadata/metadata.json` → `review_information.notes`

### Deploy Review Materials

```bash
# Ensure demo video is in place
ls website/review-4a125b1d/demo-video.mp4

# Deploy to website
./scripts/deploy-website.sh

# Verify URLs
curl -I https://contextify.sh/review-4a125b1d/sample-data.zip
curl -I https://contextify.sh/review-4a125b1d/demo-video.mp4
```

### Regenerating Sample Data

If transcript format changes:

```bash
cd appstore-metadata/review-materials
./generate-transcripts.sh
zip -r sample-data.zip sample-transcripts/ -x "*.DS_Store"
cp sample-data.zip ../../website/review-4a125b1d/
```

---

## Post-Release Verification

### Version Sync Audit

All sources must show the same version:

```bash
# Xcode project
grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1

# Git tag
git tag -l "v*" --sort=-v:refname | head -1

# Appcast
curl -s https://contextify.sh/appcast.xml | grep shortVersionString | head -1

# GitHub release
gh release list --limit 1
```

### Functional Verification

- [ ] DMG downloads from contextify.sh
- [ ] DMG installs and launches on clean Mac
- [ ] Existing DMG install receives Sparkle update notification
- [ ] App Store build appears in TestFlight (internal testing)
- [ ] App Store submission status is "Waiting for Review" or "In Review"

---

## Handling App Store Rejections

### Common Rejection Reasons

| Reason | Fix Location |
|--------|--------------|
| Crash on launch | Code fix → rebuild → re-upload |
| Missing privacy policy | App Store Connect metadata |
| Guideline 2.1 (incomplete) | Code fix or metadata clarification |
| Guideline 4.2 (minimum functionality) | Appeal or add features |
| Screenshot mismatch | Update screenshots in App Store Connect |
| Entitlement issues | Fix entitlements → rebuild → re-upload |

### Response Workflow

1. **Read rejection details**
   - App Store Connect → App → Activity → Build → View Resolution Center

2. **Record the rejection:**
   ```bash
   ./scripts/release/mark-rejected.sh X.Y.Z --interactive
   # Or: --guideline "2.1" --reason "Needs demo video"
   ```

3. **Assess the issue**
   - Metadata only? → Fix in App Store Connect
   - Code required? → Fix, rebuild, re-upload
   - Disagree? → Use Resolution Center to appeal

4. **If code fix needed:**
   ```bash
   # Fix the issue in code
   # Test thoroughly

   # Reset for new build (increments build number)
   ./scripts/release/init.sh X.Y.Z --reset

   # Rebuild and re-upload
   ./scripts/release/build.sh X.Y.Z
   bash scripts/xc.sh upload

   # Record new submission
   ./scripts/release/mark-submitted.sh X.Y.Z --build N
   ```

5. **If appealing:**
   - Use Resolution Center in App Store Connect
   - Be professional and specific
   - Reference relevant guidelines
   - Provide evidence/screenshots if applicable

### Multiple Rejections

If repeatedly rejected:
- Consider TestFlight beta to gather feedback
- Review Apple's App Review Guidelines thoroughly
- Check Apple Developer Forums for similar cases
- Contact Apple Developer Support if stuck

---

## Version Backdating

**Scenario:** You've continued development past what was submitted to App Store (e.g., code is at "1.1.0" level) but want to release it as 1.0.0 to match the pending App Store submission.

**Prerequisites:**
- DMG has NOT been released publicly yet
- No public git tag for the higher version
- App Store submission is pending (not yet approved/released)

### Procedure

1. **Update version in Xcode project:**
   ```bash
   # Find current version
   grep MARKETING_VERSION Contextify/Contextify.xcodeproj/project.pbxproj | head -1

   # Edit project.pbxproj - change MARKETING_VERSION to target version
   # (release.py can do this, or edit manually)
   ```

2. **Clean up git tags (if any exist for higher version):**
   ```bash
   # List tags
   git tag -l "v*"

   # Delete local tag (if exists)
   git tag -d v1.1.0

   # Delete remote tag (if pushed)
   git push origin --delete v1.1.0
   ```

3. **Create correct tag:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. **Build both distributions:**
   ```bash
   # DMG
   python3 scripts/release.py --version 1.0.0 --yes
   # Or if version already set:
   bash scripts/xc.sh Release build
   python3 scripts/sign_and_notarize.py

   # App Store
   bash scripts/xc.sh --dist=appstore Release archive
   bash scripts/xc.sh export-pkg
   bash scripts/xc.sh upload
   ```

5. **Update App Store Connect:**
   - Select the new build for version 1.0.0
   - Resubmit if needed

6. **Proceed with normal release:**
   - Sparkle signing
   - Appcast update
   - Website deployment

### Why This Works

- App Store only cares about the version number in the binary
- You can upload multiple builds for the same version
- The "latest" build for a version is what gets reviewed/released
- Git history is preserved; only the version number changes

### Caution

- Don't backdate if DMG already released (version confusion for users)
- Don't backdate if git tag already public (confuses contributors)
- Document the decision in commit message: "chore: backdate version to 1.0.0 for App Store alignment"

---

## Rollback (Emergency)

If a bad release ships:

### DMG Rollback

1. **Update appcast.xml** - Remove bad version or make previous version "latest"
2. **Previous DMGs remain on server** - Users get previous version on next Sparkle check
3. **Optionally:** Upload hotfix as X.Y.Z+1

```bash
# SSH to server
ssh web@banagale.com

# Edit appcast to remove/demote bad version
vim /var/www/contextify.sh/appcast.xml

# Keep previous DMGs available
ls /var/www/contextify.sh/releases/
```

### App Store Rollback

Options are limited once approved:
1. **Expedited review** for hotfix version
2. **Remove from sale** temporarily (Settings → App Availability)
3. **Contact Apple** for urgent issues affecting users

---

## Automation Status

| Step | Automated | Manual |
|------|-----------|--------|
| Version bump | ✓ release.py | - |
| Git tag | ✓ release.py | - |
| Build DMG | ✓ release.py | - |
| Sign + notarize | ✓ release.py | - |
| GitHub release | ✓ release.py | - |
| Sparkle sign | ✗ | `sparkle/sign.sh` |
| Appcast update | ✗ | Edit XML |
| Release notes | ✗ | Create HTML |
| Website deploy | ✗ | scp |
| App Store build | Partial | `xc.sh` commands |
| App Store metadata | ✗ | App Store Connect |

**Future:** P1-SPARKLE-RELEASE will automate Sparkle signing through website deployment.

---

## Files Reference

| File | Purpose |
|------|---------|
| `scripts/release.py` | DMG release automation |
| `scripts/sign_and_notarize.py` | Code signing + notarization |
| `scripts/sparkle/sign.sh` | Sparkle EdDSA signing |
| `scripts/xc.sh` | Build wrapper (--dist flag) |
| `website/appcast.xml` | Sparkle update feed |
| `website/release-notes/*.html` | Per-version release notes |
| `ExportOptions-AppStore.plist` | App Store export config |

---

**Last Updated:** 2025-11-27
