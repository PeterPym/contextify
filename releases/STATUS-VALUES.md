# Release Status Values

## DMG Channel

| Status | Meaning | Set By |
|--------|---------|--------|
| `pending` | Not yet built | `init.sh` |
| `built` | Artifacts archived, not shipped | `build.sh` |
| `shipped` | Released to users | `mark-shipped.sh --dmg` |
| `skipped` | Will not ship this version | `mark-shipped.sh --dmg --skipped` |

## App Store Channel

| Status | Meaning | Set By |
|--------|---------|--------|
| `pending` | Not yet built | `init.sh` |
| `built` | Archive/pkg ready | `build.sh` |
| `submitted` | Uploaded and submitted for review | `mark-submitted.sh` |
| `approved` | Available on App Store | `mark-shipped.sh --appstore` |
| `rejected` | Rejected by Apple | `mark-rejected.sh` |
| `skipped` | Will not ship this version | `mark-shipped.sh --appstore --skipped` |

## Overall Release Status

The top-level `release.status` field in manifest.json tracks the overall release state:

| Status | Meaning | Set By |
|--------|---------|--------|
| `in_progress` | Release is in progress | `init.sh` |
| `complete` | Both channels done | `mark-shipped.sh` (automatic) |

**Note:** `complete` is the *overall release* status, NOT a per-channel status. A release is automatically marked `complete` when:
- DMG is `shipped` or `skipped`, AND
- App Store is `approved` or `skipped`

## Notes

- `building` and `in_review` are not tracked (synchronous build, no ASC polling)
- Legacy value `complete` in DMG status is treated as `shipped` for compatibility
