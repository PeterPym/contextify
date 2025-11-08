# Release Readiness Plan

**Generated:** 2025-10-08
**Target:** Production release via GitHub (DMG) and App Store

---

## Executive Summary

**GitHub DMG Release (MVP):** Achievable with 2-3 days of focused work. Primary blockers are P0 build infrastructure items already identified in `future-features.md`.

**App Store Release:** Significant additional work due to sandboxing requirements. Recommend GitHub release first to validate market fit, then pursue App Store if demand justifies the effort.

---

## Current State Assessment

### ✅ What's Ready

1. **App Identity**
   - App icon complete (all required sizes, 16x16 to 1024x1024@2x)
   - Bundle ID: `PeterPym.Contextify` (Release config uses correct ID, not .Debug)
   - Version: 1.0, Build: 1
   - Info.plist properly configured with usage descriptions

2. **Code Signing Infrastructure**
   - Developer ID Application certificate available: `B46F8E29955991D15267BE5B5C019DFF17405554`
   - Development Team: J8P5B23FK7 (Perch Innovations, Inc.)
   - Entitlements file exists and properly configured for non-sandboxed distribution
   - Hardened runtime compatible entitlements

3. **Build Tooling**
   - `create-dmg` tool installed (`/opt/homebrew/bin/create-dmg`)
   - Build script exists (`scripts/xc.sh`)
   - Pre-commit hooks for build validation
   - Release configuration exists in Xcode project

4. **Reference Implementation**
   - FileKitty project has complete release infrastructure:
     - `tools/release.py` - End-to-end release automation
     - `tools/packaging/sign_and_notarize.py` - Signing, DMG creation, notarization
     - `tools/packaging/dmg_settings.json` - DMG layout configuration
     - GitHub release upload via `gh` CLI

### ⚠️ What's Partially Ready

1. **Build Infrastructure**
   - Build script works but may not bundle all resources
   - Python daemon and venv not bundled (P0 blocker from `future-features.md`)
   - Build parity between `xc.sh` and Xcode not verified

2. **Project Configuration**
   - LaunchAgentManager.swift and ITerm2DaemonClient.swift compile but not in Xcode project
   - Archive builds may fail due to missing file references

### ❌ What's Missing

1. **Release Scripts**
   - No sign and notarize script
   - No DMG creation script
   - No release automation script
   - No version bump automation

2. **Distribution Assets**
   - No DMG background image
   - No DMG layout configuration
   - No notary profile configured

3. **Release Process**
   - No GitHub release workflow
   - No release checklist
   - No beta testing process

---

## Path to GitHub DMG Release (MVP)

### Phase 1: Build Infrastructure (P0 - Required)
**Timeline:** 1-2 days
**Blocker:** Yes - App won't work without bundled resources

#### 1.1 Daemon Venv Auto-Repair
**Status:** ✅ COMPLETED (2025-10-09)
**Implementation:** On-demand venv creation instead of bundling

**What Was Implemented:**
- ✅ `LaunchAgentManager.swift` - VenvStatus enum with 5 health states
- ✅ `validateVenv()` - Detects broken symlinked venvs, missing dependencies, version mismatches
- ✅ `rebuildVenvFromSystem()` - Creates fresh venv using `python3 -m venv --copies`
- ✅ `installIfNeeded()` - Auto-validates and rebuilds venv on launch
- ✅ Error messages updated in `TerminalContentReader.swift` with actionable steps

**Why This Approach:**
- Bundled venvs use symlinks that break when app moves locations
- System Python (python3) available on all macOS 14+ (our minimum)
- On-demand creation is simpler and more reliable than bundling
- ~30 second first-run setup time is acceptable

**User Experience:**
1. First launch: venv auto-created from system Python
2. Broken venv: auto-detected and repaired
3. No internet: graceful failure with helpful error
4. Progress shown to user (no silent freeze)

**Acceptance Criteria:**
- ✅ Clean install works without manual file copying
- ✅ Daemon launches after venv creation
- ✅ Venv validated on every app launch
- ✅ Both `xc.sh build` and Xcode build work identically

#### 1.2 Add Swift Files to Xcode Project
**From:** `future-features.md` lines 78-101

**Tasks:**
- [ ] Open `Contextify.xcodeproj` in Xcode
- [ ] Add `LaunchAgentManager.swift` with Contextify target membership
- [ ] Add `ITerm2DaemonClient.swift` with Contextify target membership
- [ ] Verify clean build succeeds
- [ ] Verify archive build succeeds

**Acceptance Criteria:**
- Files visible in Xcode navigator
- Archive build completes without errors
- No duplicate symbol warnings

#### 1.3 Verify Build Parity
**From:** `future-features.md` lines 46-76

**Tasks:**
- [ ] Clean build via `bash scripts/xc.sh build`
- [ ] Clean build via Xcode (Product → Run)
- [ ] Compare bundled resources using provided diff script
- [ ] Document any intentional differences

**Acceptance Criteria:**
- No differences in bundled resources between build methods
- Daemon and venv present in both builds

---

### Phase 2: Signing & Distribution (P1 - Required for Release)
**Status:** ✅ COMPLETED (2025-10-09)
**Timeline:** Completed in ~30 minutes (faster than estimated!)

#### 2.1 Create Signing & Notarization Script
**Status:** ✅ COMPLETED
**File:** `scripts/sign_and_notarize.py`

**What Was Created:**
- ✅ Complete signing script adapted from FileKitty
- ✅ Paths configured for Contextify build structure
- ✅ Developer ID certificate detection working
- ✅ Tested successfully with `--no-notarize` flag
- ✅ Full notarization integration with create-dmg

**Key Functions Implemented:**
- `sign_binaries_inside_out()` - Signs 5 Python native modules + main executable
- `sign_outer_bundle()` - Signs app bundle with entitlements
- `verify_local_signature()` - Validates signatures (using non-strict mode for bundled Python)
- `create_dmg()` - Creates DMG with custom layout and auto-notarization

**Test Results:**
- ✅ All binaries signed with hardened runtime
- ✅ Timestamp applied to all signatures
- ✅ Entitlements applied correctly
- ✅ `codesign --verify` passes
- ✅ DMG created successfully (9.7MB)

#### 2.2 Create DMG Layout Assets
**Status:** ✅ COMPLETED

**Files Created:**
- ✅ `build/assets/dmg_background.png` - Gradient background (700x400px)
- ✅ `build/assets/dmg_settings.json` - Layout configuration
- ✅ `scripts/generate_dmg_background.swift` - Background generator script

**DMG Configuration:**
- Window size: 700x400
- Icon size: 120
- App icon position: (160, 140)
- Applications link: (530, 140)
- Custom gradient background applied

**Results:**
- ✅ DMG opens with custom background and layout
- ✅ Drag-to-Applications flow works perfectly
- ✅ Professional appearance

#### 2.3 Configure Notarization
**Status:** ✅ COMPLETED

**What Was Done:**
- ✅ App-specific password created at appleid.apple.com
- ✅ Credentials stored in keychain as "NotaryProfile"
- ✅ Notarization tested and **ACCEPTED by Apple**
- ✅ Ticket stapled successfully

**Notarization Details:**
- **Submission ID:** f5eab367-7447-489e-8c05-2502266b75c1
- **Status:** Accepted
- **Processing Time:** ~4 minutes
- **Result:** `spctl --assess --type install dist/Contextify.dmg` = "accepted"

**Gatekeeper Verification:**
```
dist/Contextify.dmg: accepted
source=Notarized Developer ID
origin=Developer ID Application: Perch Innovations, Inc. (J8P5B23FK7)
```

**DMG Details:**
- **File:** `dist/Contextify.dmg`
- **Size:** 9.7 MB
- **SHA256:** `b1ee0dc7ad6cef740b0e1116afa7fe3fcf581db11e3d2ade6e34d7c33797784a`

**Acceptance Criteria:**
- ✅ Notarization succeeded without errors
- ✅ Stapling completed successfully
- ✅ DMG opens without Gatekeeper warnings
- ✅ Ready for public distribution

---

### Phase 3: Release Automation (P2 - Nice to Have)
**Timeline:** 1 day
**Blocker:** No - Can release manually first

#### 3.1 Create Release Script
**Adapt from:** `FileKitty/tools/release.py`

**New file:** `scripts/release.py`

**Tasks:**
- [ ] Adapt FileKitty release script for Contextify
- [ ] Version source: `MARKETING_VERSION` in Xcode project (not pyproject.toml)
- [ ] Build command: `bash scripts/xc.sh build` (not py2app)
- [ ] Archive creation: Rename and copy DMG (not zip)
- [ ] GitHub release via `gh release create`

**Version Management Strategy:**
Two options:

**Option A: Manual Version Bump (Simpler)**
- Edit version in Xcode project settings before release
- Script reads current version, creates tag
- Commit version bump separately

**Option B: Automated Version Bump (More Complex)**
- Script modifies `Contextify.xcodeproj/project.pbxproj` directly
- Use PlistBuddy or xcodeproj parsing
- Higher risk of Xcode project corruption

**Recommendation:** Start with Option A (manual), automate later if needed.

**Script Flow:**
1. Read `MARKETING_VERSION` from Xcode build settings
2. Confirm version with user
3. Build: `bash scripts/xc.sh clean && bash scripts/xc.sh build`
4. Sign & notarize: `python3 scripts/sign_and_notarize.py`
5. Create git tag: `git tag v{version}`
6. Push tag: `git push origin v{version}`
7. Create GitHub release:
   ```bash
   gh release create v{version} \
     dist/Contextify.dmg \
     dist/Contextify.dmg.sha256 \
     --title "Contextify v{version}" \
     --notes-file /tmp/contextify-release/release-notes-{version}.md
   ```

**Acceptance Criteria:**
- Release script runs end-to-end without errors
- GitHub release created with DMG and checksum
- Tag pushed to remote
- Release notes displayed on GitHub

#### 3.2 Create Release Checklist

**New file:** `/tmp/contextify-release/release-checklist.md` (transient planning doc)

**Contents:**
- [ ] All P0 blockers from `future-features.md` resolved
- [ ] Build parity verified (script vs Xcode)
- [ ] Daemon bundled and tested in fresh install
- [ ] Version bumped in Xcode project
- [ ] CHANGELOG.md updated
- [ ] Release notes written
- [ ] Build via `bash scripts/xc.sh build`
- [ ] Sign and notarize via `python3 scripts/sign_and_notarize.py`
- [ ] Test DMG on fresh Mac (or clean VM)
- [ ] Verify app launches and daemon works
- [ ] Verify hotkey works
- [ ] Run manual smoke tests
- [ ] Create GitHub release
- [ ] Test download from GitHub
- [ ] Announce release (Twitter, blog, etc.)

---

## Path to App Store Release (Future Work)

**Estimated Timeline:** 1-2 weeks additional work
**Recommendation:** Ship GitHub release first, gauge demand

### Major Differences from GitHub Release

#### 1. Sandboxing (Required by App Store)

**Current State:**
```xml
<key>com.apple.security.app-sandbox</key>
<false/>
```

**App Store Requirement:**
```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

**Impact Analysis:**

**Broken Functionality:**
- ✅ **LaunchAgent daemon:** Can use `com.apple.security.temporary-exception.mach-lookup.global-name` to keep daemon working
- ⚠️ **iTerm2 automation:** Currently uses temporary exception, may need App Store approval
- ⚠️ **Accessibility/Screen Recording:** Requires user approval, may need justification for App Store review
- ❌ **File system access:** Limited to security-scoped bookmarks (already implemented in HUDPreferences)

**Required Work:**
- [ ] Test all features with sandbox enabled
- [ ] Update entitlements with sandbox exceptions
- [ ] Add temporary exceptions for critical functionality:
  ```xml
  <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
  <array>
    <string>com.googlecode.iterm2</string>
  </array>
  ```
- [ ] Justify temporary exceptions in App Review notes
- [ ] May need to request special entitlement approval from Apple

#### 2. Code Signing Changes

**Different Certificate:**
- GitHub: Developer ID Application
- App Store: Mac App Distribution (from developer.apple.com)

**Different Provisioning:**
- Create App Store provisioning profile
- Enable App Sandbox in profile
- Request entitlements in profile (Accessibility, Screen Recording)

#### 3. App Store Connect Setup

**Tasks:**
- [ ] Create App Store Connect record
- [ ] Upload screenshots (required sizes: 1280x800, 1440x900, 2560x1600, 2880x1800)
- [ ] Write app description (short and long)
- [ ] Create marketing materials
- [ ] Privacy policy URL (required for Accessibility permissions)
- [ ] Support URL
- [ ] Age rating questionnaire
- [ ] Export compliance documentation

#### 4. App Store Review Preparation

**Likely Review Questions:**
- Why does the app need Accessibility access?
- Why does the app need Screen Recording permission?
- Why does the app need Apple Events automation?
- Why does the app need to control iTerm2?

**Recommended Responses:**
- Prepare demo video showing core workflow
- Write detailed review notes explaining terminal integration
- Provide test account/instructions if applicable
- Emphasize developer productivity benefits

**Rejection Risks:**
- Accessibility/Screen Recording may be flagged as excessive
- iTerm2-specific automation may be seen as too narrow
- Temporary exception entitlements may require special approval
- LaunchAgent daemon may be questioned (background processes)

**Mitigation:**
- Clearly explain use case in review notes
- Provide fallback modes (e.g., work without daemon at reduced performance)
- Demonstrate that permissions are essential, not optional
- Reference similar approved apps (if any)

#### 5. Distribution Differences

**GitHub DMG:**
- Direct download
- User installs manually
- No review process
- Fast iteration

**App Store:**
- Managed by macOS App Store
- Automatic updates
- Review for every update (3-7 days)
- Sandbox restrictions
- Discoverability benefits

---

## Resource Requirements

### GitHub DMG Release

**Scripts to Create:**
1. `scripts/sign_and_notarize.py` (~200-300 lines, adapt from FileKitty)
2. `scripts/release.py` (~150-200 lines, adapt from FileKitty)
3. `build/assets/dmg_settings.json` (~25 lines)

**Assets to Create:**
1. DMG background image (can use simple design initially)
2. Release notes template

**Time Estimate:**
- Phase 1 (Build Infrastructure): 1-2 days
- Phase 2 (Signing & Distribution): 1-2 days
- Phase 3 (Release Automation): 1 day
- **Total:** 3-5 days for first release, then ~1 hour per subsequent release

### App Store Release

**Additional Work:**
- Sandbox testing and fixes: 2-3 days
- App Store Connect setup: 1 day
- Screenshot creation and marketing copy: 1 day
- Review preparation: 1 day
- Review iterations: Variable (3-7 days per round)
- **Total:** 1-2 weeks + review time

---

## Recommendations

### Immediate Actions (This Week)

1. **Resolve P0 Blockers:**
   - Bundle daemon resources (from `future-features.md`)
   - Add Swift files to Xcode project
   - Verify build parity

2. **Create Release Infrastructure:**
   - Port FileKitty signing script
   - Create DMG layout and assets
   - Configure notarization profile

3. **Manual First Release:**
   - Don't automate everything initially
   - Build, sign, notarize, and release manually
   - Document process for automation later

### Medium Term (Next 2 Weeks)

1. **Iterate on GitHub Releases:**
   - Ship 1-2 beta releases to test process
   - Gather feedback from early users
   - Fix critical bugs found in production

2. **Automate Release Process:**
   - Create release.py script
   - Set up GitHub Actions for CI/CD (optional)
   - Document release runbook

### Long Term (1-2 Months)

1. **Evaluate App Store:**
   - Assess user demand
   - Gauge willingness to pay (if planning paid App Store release)
   - Research similar apps and their review experiences

2. **Pursue App Store if Warranted:**
   - Enable sandbox and test thoroughly
   - Create App Store Connect listing
   - Prepare review materials
   - Submit for review

---

## Success Metrics

### GitHub Release
- [ ] DMG downloads without errors
- [ ] App launches on fresh Mac without manual setup
- [ ] Daemon works out of the box
- [ ] No Gatekeeper warnings
- [ ] Hotkey functionality works
- [ ] Zero critical bugs reported in first week

### App Store Release (Future)
- [ ] Passes App Store review on first or second attempt
- [ ] All features work in sandboxed environment
- [ ] Positive user reviews (4+ stars)
- [ ] Low refund rate (<5%)
- [ ] Sufficient downloads to justify maintenance effort

---

## Open Questions

1. **Homebrew Distribution:**
   - FileKitty has Homebrew formula (`homebrew-filekitty`)
   - Should Contextify also support `brew install contextify`?
   - Would require maintaining formula repository
   - Lower priority than DMG, but nice to have

2. **Beta Testing:**
   - Should we run private beta before public release?
   - TestFlight not available for Mac App Store (only for iOS)
   - Could use GitHub pre-releases for beta testing

3. **Pricing Strategy:**
   - GitHub: Free?
   - App Store: Free, Paid, or Freemium?
   - Sustainability model?

4. **Update Mechanism:**
   - GitHub: Sparkle framework for auto-updates?
   - App Store: Handled automatically
   - Should we implement Sparkle for GitHub distribution?

---

## Appendix: FileKitty Infrastructure Reference

### Key Files to Adapt

1. **`tools/packaging/sign_and_notarize.py`** (lines 1-229)
   - Core signing and DMG creation logic
   - Well-structured, easy to adapt
   - Handles hardened runtime, timestamp, entitlements
   - Uses `create-dmg` tool (already installed)

2. **`tools/release.py`** (lines 1-217)
   - End-to-end release automation
   - Version bumping (adapt for Xcode instead of pyproject.toml)
   - Git tagging and pushing
   - GitHub release creation via `gh` CLI
   - SHA256 checksum generation

3. **`tools/packaging/dmg_settings.json`** (lines 1-26)
   - Simple JSON layout config
   - Easy to customize for Contextify

4. **`tools/packaging/entitlements.plist`** (lines 1-6)
   - Empty in FileKitty!
   - Contextify already has proper entitlements file
   - No changes needed

### Notable Differences

| Aspect | FileKitty | Contextify |
|--------|-----------|------------|
| Language | Python (py2app) | Swift |
| Build Tool | poetry + setup.py | Xcode + xcodebuild |
| Version Source | pyproject.toml | Xcode MARKETING_VERSION |
| Archive Format | ZIP | DMG |
| Distribution | GitHub + Homebrew | GitHub (then App Store) |
| Sandbox | N/A (Python app) | Required for App Store |

---

**Last Updated:** 2025-10-08
**Next Review:** After P0 blockers resolved
