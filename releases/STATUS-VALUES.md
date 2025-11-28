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

## Notes

- `building` and `in_review` are not tracked (synchronous build, no ASC polling)
- Legacy value `complete` is treated as `shipped` for DMG compatibility
