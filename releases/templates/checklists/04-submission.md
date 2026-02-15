# Submission Checklist

**Release:** {version}
**Phase:** 4 of 6
**Status:** [ ] Not Started / [ ] In Progress / [ ] Complete

## Pre-Submission Verification

### Verify Prerequisites
- [ ] Build artifacts exist (Phase 2 complete)
- [ ] Review materials deployed (Phase 3 complete)
- [ ] Sample data URL works
- [ ] Demo video URL works

## App Store Upload

### Upload Build
- [ ] Run: `bash scripts/xc.sh upload`
- [ ] Upload successful: [ ] Yes / [ ] No
- [ ] If failed, check error and retry

### Wait for Processing
- [ ] Check App Store Connect for build availability
- [ ] Build appears in TestFlight: [ ] Yes (continue) / [ ] No (wait)
- [ ] Processing time: ____ minutes

## App Store Connect

### Select Build
- [ ] Open: https://appstoreconnect.apple.com/apps/6753190666/distribution/macos/version/inflight
- [ ] Select new build (build number: ____)
- [ ] Build selected successfully

### Review & Update Metadata

Review App Store listing content before submission:
- [ ] Parse `appstore-metadata/metadata.json` - source of truth
- [ ] System requirements still accurate?
- [ ] Feature list reflects current capabilities?
- [ ] What's New text updated for this version?
- [ ] Screenshots show current UI? (if UI changed significantly)
- [ ] Keywords still relevant?

If changes needed, update `metadata.json` and upload:
```bash
FASTLANE_API_KEY_PATH=".secrets/fastlane_api_key.json" fastlane deliver \
  --skip_binary_upload --skip_screenshots --force --run_precheck_before_submit false
```
- [ ] Metadata uploaded (or no changes needed)

### Review Information
- [ ] Paste review notes from: `appstore-metadata/fastlane/metadata/review_information/notes.txt`
- [ ] Notes include sample data URL
- [ ] Notes include demo video URL
- [ ] Notes include setup instructions

### Export Compliance
- [ ] Export compliance answered (usually: No encryption beyond standard HTTPS)

## Submit for Review

- [ ] Click "Submit for Review"
- [ ] Submission confirmed: [ ] Yes / [ ] No
- [ ] Submission time: ____

### Take Screenshot
- [ ] Screenshot submission confirmation
- [ ] Save to: `releases/v{version}/assets/submission-screenshot.png`

## Record Submission

```bash
# Record in tracking system
./scripts/release/mark-submitted.sh {version} --build ____
```

This updates both `release.json` and `manifest.json` automatically.

## Handling Rejection (if applicable)

If rejected:
- [ ] Read rejection reason in App Store Connect Resolution Center
- [ ] Record rejection:
  ```bash
  ./scripts/release/mark-rejected.sh {version} --interactive
  ```
- [ ] Determine fix:
  - Metadata issue? Fix in App Store Connect, resubmit same build
  - Code issue? Fix code, reset for new build:
    ```bash
    ./scripts/release/init.sh {version} --reset
    # Return to Phase 2 (build)
    ```
- [ ] Address rejection and resubmit

**Rejection details (if applicable):**
- Date: ____
- Guideline: ____
- Reason: ____
- Action taken: ____

## Sign-off

- [ ] Build uploaded successfully
- [ ] Metadata complete
- [ ] Review notes include all required information
- [ ] Submitted for review
- [ ] Ready for Phase 5: Marketing (can start in parallel)

**Completed by:** ____
**Date:** ____
