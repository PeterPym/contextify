# Release v1.0.0

**Created:** 2025-11-25
**Status:** Pending Resubmission (App Store rejected, preparing to resubmit)

## Quick Status

| Phase | Status |
|-------|--------|
| 1. Pre-Release | Complete |
| 2. Build | Complete |
| 3. Review Materials | In Progress |
| 4. Submission | Pending Resubmission |
| 5. Marketing | Not Started |
| 6. Post-Release | Not Started |

## Current Situation

- **DMG:** Released via GitHub (v1.0.0 tag)
- **App Store:** Rejected on 2025-11-26 (Guideline 2.1 - needs demo video and sample data)
- **Next step:** Record demo video, deploy review materials, resubmit

## Rejection Details

**Guideline:** 2.1 - Information Needed
**Reason:** Unable to review - requires demo video and sample data
**Response:** Created sample transcripts (57 files), demo video script ready

## Checklists

- [`01-pre-release.md`](checklists/01-pre-release.md) - Complete
- [`02-build.md`](checklists/02-build.md) - Complete
- [`03-review-materials.md`](checklists/03-review-materials.md) - In Progress
- [`04-submission.md`](checklists/04-submission.md) - Pending Resubmission
- [`05-marketing.md`](checklists/05-marketing.md) - Not Started
- [`06-post-release.md`](checklists/06-post-release.md) - Not Started

## Files

- `release.json` - Complete release state
- `checklists/` - Phase checklists
- `artifacts/` - Build artifact references
- `logs/` - Validation outputs
- `assets/` - Screenshots, metadata snapshots

## Commands

```bash
# Check status
./scripts/release/status.sh 1.0.0

# Validate build
./scripts/release/validate-build.sh 1.0.0
```

## Immediate Next Steps

1. Deploy website with review materials:
   ```bash
   ./scripts/deploy-website.sh
   ```

2. Build App Store archive (build 4):
   ```bash
   bash scripts/xc.sh --dist=appstore Release archive
   ```

3. Record demo video following:
   `appstore-metadata/review-materials/DEMO-VIDEO-SCRIPT.md`

4. Upload and resubmit in App Store Connect
