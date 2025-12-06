# Release Status Values

## Target Channels

The `target_channels` field specifies which distribution channels a release targets. It is set at release initialization and is immutable.

| Value | Meaning |
|-------|---------|
| `["dmg"]` | DMG-only release (direct download) |
| `["appstore"]` | App Store-only release |
| `["dmg", "appstore"]` | Both channels |

**Rules:**
- `target_channels` is required and must contain at least one value
- Non-targeted channels should have status `skipped`
- Guards prevent operations on non-targeted channels (e.g., can't submit to App Store if not targeted)

**Set by:** `init.sh --dmg`, `init.sh --appstore`, or `init.sh --both`

---

## DMG Channel

| Status | Meaning | Set By |
|--------|---------|--------|
| `pending` | Not yet built | `init.sh` |
| `built` | Artifacts archived, not shipped | `build.sh` |
| `shipped` | Released to users | `mark-shipped.sh --dmg` |
| `skipped` | Will not ship this version | `mark-shipped.sh --dmg --skipped` |

## App Store Channel

### Local Tracking Status

| Status | Meaning | Set By |
|--------|---------|--------|
| `pending` | Not yet built | `init.sh` |
| `built` | Archive/pkg ready | `build.sh` |
| `submitted` | Submitted to App Store for review | `mark-submitted.sh` |
| `approved` | Approved by Apple | `mark-shipped.sh --appstore` |
| `rejected` | Rejected by Apple (non-terminal) | `mark-rejected.sh` |
| `skipped` | Will not ship this version | `init.sh` (for non-targeted) |

### Apple State (from App Store Connect API)

The `apple_state` field contains the actual state from Apple. Use `poll-appstore-status.sh` to sync.

#### Submission States

| Apple State | Category | Meaning | Action Required |
|-------------|----------|---------|-----------------|
| `PREPARE_FOR_SUBMISSION` | not_submitted | Draft version, metadata incomplete | Complete metadata, submit |
| `READY_FOR_REVIEW` | not_submitted | Ready but not submitted | Click "Submit for Review" |
| `WAITING_FOR_REVIEW` | in_review | Submitted, in Apple's queue | Wait |
| `IN_REVIEW` | in_review | Under active review | Wait |
| `WAITING_FOR_EXPORT_COMPLIANCE` | in_review | Needs export compliance answer | Answer in ASC |
| `PENDING_CONTRACT` | in_review | Waiting on legal/contract | Resolve in ASC |

#### Approved States

| Apple State | Category | Meaning | Action Required |
|-------------|----------|---------|-----------------|
| `PENDING_DEVELOPER_RELEASE` | approved | Approved, awaiting manual release | Click "Release" in ASC |
| `PENDING_APPLE_RELEASE` | approved | Approved, scheduled release pending | Wait for date |
| `PROCESSING_FOR_APP_STORE` | approved | Being processed to go live | Wait (minutes) |
| `READY_FOR_SALE` | approved | Live on App Store | None (terminal) |
| `PREORDER_READY_FOR_SALE` | approved | Pre-order available | None |
| `ACCEPTED` | approved | Accepted (legacy state) | None |

#### Rejected States

| Apple State | Category | Meaning | Action Required |
|-------------|----------|---------|-----------------|
| `METADATA_REJECTED` | rejected | Metadata rejected | Fix in ASC, resubmit same build |
| `REJECTED` | rejected | Binary rejected | Fix code, rebuild, re-upload |
| `INVALID_BINARY` | rejected | Corrupt/invalid binary | Rebuild, re-upload |

#### Removed States

| Apple State | Category | Meaning | Action Required |
|-------------|----------|---------|-----------------|
| `DEVELOPER_REJECTED` | removed | Developer cancelled submission | Resubmit when ready |
| `DEVELOPER_REMOVED_FROM_SALE` | removed | Developer pulled from sale | Re-enable if desired |
| `REMOVED_FROM_SALE` | removed | Removed by Apple | Contact Apple |

#### Other States

| Apple State | Category | Meaning | Action Required |
|-------------|----------|---------|-----------------|
| `REPLACED_WITH_NEW_VERSION` | other | Superseded by newer version | None (terminal) |
| `NOT_APPLICABLE` | other | N/A | None |

### State Category Mapping

For workflow logic, Apple states map to categories:

```
not_submitted: PREPARE_FOR_SUBMISSION, READY_FOR_REVIEW
in_review:     WAITING_FOR_REVIEW, IN_REVIEW, WAITING_FOR_EXPORT_COMPLIANCE, PENDING_CONTRACT
approved:      PENDING_DEVELOPER_RELEASE, PENDING_APPLE_RELEASE, PROCESSING_FOR_APP_STORE,
               READY_FOR_SALE, PREORDER_READY_FOR_SALE, ACCEPTED
rejected:      METADATA_REJECTED, REJECTED, INVALID_BINARY
removed:       DEVELOPER_REJECTED, DEVELOPER_REMOVED_FROM_SALE, REMOVED_FROM_SALE
other:         REPLACED_WITH_NEW_VERSION, NOT_APPLICABLE
```

## Overall Release Status

The top-level `release.status` field in manifest.json tracks the overall release state:

| Status | Meaning | Set By |
|--------|---------|--------|
| `in_progress` | Release is in progress | `init.sh` |
| `complete` | Both channels done | `mark-shipped.sh` (automatic) |

**Note:** `complete` is the *overall release* status, NOT a per-channel status. A release is automatically marked `complete` when:
- Every targeted channel is in a terminal state (DMG `shipped`, App Store `approved`), AND
- Non-targeted channels are `skipped`, AND
- All marketing and post-release phases are complete

## Syncing with App Store Connect

To check actual Apple status:

```bash
# Query current status
./scripts/release/poll-appstore-status.sh 1.0.0

# Auto-update local state from Apple
./scripts/release/poll-appstore-status.sh 1.0.0 --sync
```

## Schema Reference

See `releases/schemas/` for JSON Schema definitions:
- `appstore-states.schema.json` - All Apple states with category mapping
- `manifest.schema.json` - manifest.json structure
- `release.schema.json` - Per-release detail structure
- `config.schema.json` - Static configuration

## Notes

- Legacy value `complete` in DMG status is treated as `shipped` for compatibility
- Legacy values `submitted`, `approved`, `rejected` in App Store status are deprecated; use `apple_state` instead
