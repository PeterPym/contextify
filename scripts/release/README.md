---
title: Release Workflow Scripts
purpose: Release orchestration helpers for DMG and App Store builds.
audience: Release engineers and automation (including AI agents).
status: active
---

# Release Workflow Scripts

Release automation helpers used by the guided workflow.
Start with `releases/WORKFLOW.md` for the full process.

## Quick Start

```bash
./scripts/release/context.sh
./scripts/release/status.sh
```

## Core Commands

| Script | Purpose |
|--------|---------|
| `context.sh` | Show current release context and next action |
| `init.sh` | Initialize a release version and targets |
| `build.sh` | Build release artifacts for targeted channels |
| `status.sh` | Show release status and next steps |
| `validate-pre-release.sh` | Run pre-release checks |
| `mark-submitted.sh` | Record App Store submission |
| `mark-shipped.sh` | Record release shipment |

## References

- `scripts/RELEASE.md`
- `releases/WORKFLOW.md`
