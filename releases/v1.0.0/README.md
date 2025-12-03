# Release v1.0.0

**Created:** 2025-11-28
**Status:** In Progress
**Build:** 10

## Quick Status

| Phase | Status |
|-------|--------|
| 1. Pre-Release | Pending |
| 2. Build | Pending |
| 3. Review Materials | Pending |
| 4. Submission | Pending |
| 5. Marketing | Pending |
| 6. Post-Release | Pending |

## Checklists

- [`01-pre-release.md`](checklists/01-pre-release.md)
- [`02-build.md`](checklists/02-build.md)
- [`03-review-materials.md`](checklists/03-review-materials.md)
- [`04-submission.md`](checklists/04-submission.md)
- [`05-marketing.md`](checklists/05-marketing.md)
- [`06-post-release.md`](checklists/06-post-release.md)

## Files

- `release.json` - Complete release state
- `checklists/` - Phase checklists
- `artifacts/` - Build artifact references
- `logs/` - Validation outputs
- `assets/` - Screenshots, receipts
- `rejections/` - Rejection history, research, and deliberations

## Rejections

| # | Date | Build | Guideline | Status |
|---|------|-------|-----------|--------|
| 1 | Nov 26 | 3 | 2.1 (App Completeness) | Resolved |
| 2 | Dec 3 | 10 | 2.4.5(i) (User Data Location) | Active |

**Files:**
- [`messages.md`](rejections/messages.md) - Full rejection text from Apple
- [`rejection-history.json`](rejections/rejection-history.json) - Structured rejection data
- [`rejection-2-deliberation.md`](rejections/rejection-2-deliberation.md) - Analysis and decision record
- [`macos-sandbox-database-storage-tech-brief.md`](rejections/macos-sandbox-database-storage-tech-brief.md) - Research on sandbox/database guidelines

## Commands

```bash
# Check status
./scripts/release/status.sh 1.0.0

# Validate pre-release
./scripts/release/validate-pre-release.sh 1.0.0

# Reset for new build (preserves notes)
./scripts/release/init.sh 1.0.0 --reset
```
