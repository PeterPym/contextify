---
todo_id: SMART-LAZY-WATCHERS-DELAY
title: Tap-to-switch delay investigation reference
type: reference
date: 2025-12-28
status: active
description: Known observations and initial evidence for the tap-to-switch delay regression and related watcher stop anomalies.
---

# Tap-to-Switch Delay Investigation Reference

## Symptom Summary

- Extended latency between user tap and project switch start.
- Example log gap: `[BUTTON-TAP] CLICKED` at 10:12:28.248, switch flow starts at 10:12:50.740 (18–22s delay).

## Evidence

Source log: `/private/tmp/transcript-queue-monitor-20251228-101049.log`

- Tap events:
  - `2025-12-28 10:12:28.248` `[BUTTON-TAP] CLICKED: contextify`
  - `2025-12-28 10:12:32.483` `[BUTTON-TAP] CLICKED: contextify`
- Switch flow begins much later:
  - `2025-12-28 10:12:50.740` `[UIOPT-SWITCH-START] switchToProject()`

## Related Watcher Behavior (Possible Correlation)

- Tier assignment and watcher starts occur as expected.
- Missing `[WATCHER-STOP]` logs despite `to_stop=20` diffs.
- Heartbeat reports `watching=53` (above expected budget max ~40), suggesting watchers may not be stopping or stop logs are missing.

## Immediate Next Steps (Stub)

1) Add timing logs for tap → switch stages:
   - Tap received
   - DB lookup start/end
   - selectProject start/end
   - activeProjectId UI update
   - watcher plan apply start/end
2) Validate watcher stop path:
   - Confirm stop operations are executed when `to_stop > 0`.
   - Audit stop logging paths and ensure they emit consistently.

