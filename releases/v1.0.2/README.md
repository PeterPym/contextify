# Release v1.0.2

**Created:** 2025-12-09
**Status:** In Progress
**Build:** 1
**Targeting:** Both (DMG + App Store)

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

## Commands

```bash
# Check status
./scripts/release/status.sh 1.0.2

# Validate pre-release
./scripts/release/validate-pre-release.sh 1.0.2

# Reset for new build (preserves notes)
./scripts/release/init.sh 1.0.2 --reset
```
