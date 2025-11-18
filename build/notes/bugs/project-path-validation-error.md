# Bug: Stored Project Root Invalid/Unreadable

**Date Reported:** 2025-11-18
**Severity:** Unknown (needs investigation)

## Symptom

Modal appeared during testing showing:
```
Stored project root is invalid or unreadable (saved path):
/Users/rob/code/personal/finance
```

## Context

- Occurred during P0 discovery fix testing
- Build: DMG (unsandboxed)
- Test command: `bash scripts/xc.sh dr` (clean database)
- Appeared after welcome modal, when clicking Projects window

## Questions to Investigate

1. Why is `/Users/rob/code/personal/finance` invalid/unreadable?
   - Does directory exist?
   - Permissions issue?
   - Symlink resolution problem?

2. When does this validation occur?
   - During project switching?
   - During watcher creation?
   - On app startup?

3. Is this specific to one project or systematic?
   - Other projects load fine?
   - Is finance project actually broken or false positive?

4. Related to recent changes?
   - Did parallel watcher creation expose this?
   - Was validation always this strict?

## Reproduction

```bash
bash scripts/xc.sh dr
# Welcome modal completes
# Click Projects window
# Modal appears for /Users/rob/code/personal/finance
```

## Next Steps

1. Check if directory exists and is readable
2. Search codebase for "invalid or unreadable" error message
3. Check git logs for recent path validation changes
4. Verify if issue exists on main branch

## Log Reference

Test log: `/private/tmp/transcript-queue-monitor-20251118-081152.log` (or later)
