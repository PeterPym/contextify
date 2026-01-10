---
title: Script Helper Libraries
purpose: Shared shell helpers used across scripts.
audience: Contributors and automation (including AI agents).
status: internal
---

# Script Helper Libraries

Utilities sourced by scripts in this repository. These files are not designed
for direct execution.

## Files

| File | Purpose |
|------|---------|
| `cleanup.sh` | Shared cleanup helpers for temp files and processes |
| `db_location.sh` | Resolve database paths and configuration |
| `transcript-isolation.sh` | Helpers for transcript isolation during tests |

## Usage

Scripts typically source these helpers with `source scripts/lib/<file>.sh`.
If you add new helpers, keep them pure and side-effect free.
