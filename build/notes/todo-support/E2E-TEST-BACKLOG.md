---
todo_id: E2E-TEST-BACKLOG
title: E2E Test Coverage Backlog
type: reference
date: 2025-12-11
status: active
description: Catalog of scenarios that need E2E test coverage. Add entries as bugs are fixed or features shipped without automated tests.
---

# E2E Test Coverage Backlog

This document collects scenarios that should have E2E test coverage but don't yet. When fixing bugs or shipping features, add an entry here if manual QA was done but no automated test exists.

## How to Add Entries

When you verify a fix manually but have no E2E test:

1. Add entry with scenario description
2. Note the manual QA steps performed
3. Reference the fix commit/PR if applicable
4. Tag with category (sandbox, discovery, timeline, etc.)

---

## Entry 1: Dual-CLI Permission Grant

**Date Added:** 2025-12-11
**Category:** sandbox, permissions, discovery
**Verified In:** v1.0.1 (manual QA)

**Scenario:**
User completes onboarding with only Claude Code permission, then later grants Codex permission via Settings. Both providers should be discovered without app restart.

**Manual QA Steps Performed:**
1. Clean install (delete app, run `make clean-db`)
2. Launch app - onboarding wizard appears
3. Grant Claude Code permission only, complete onboarding
4. Verify Claude projects discovered
5. Open Settings > Permissions, grant Codex
6. Verify: Both Claude AND Codex projects now appear
7. Check logs: No `WATCHER-RECOVERY-ERROR` with sandbox container paths

**Fix Reference:**
- NotificationCenter pattern for permission change (87bf979a)
- Permission observer in AppLifecycleState singleton

**E2E Test Requirements:**
- Requires App Store (sandboxed) build
- Needs ability to simulate permission grants mid-session
- May require test fixture approach similar to QA Phase 2

**Complexity:** High (sandbox permission simulation)

---

## Template for New Entries

```markdown
---

## Entry N: [Brief scenario description]

**Date Added:** YYYY-MM-DD
**Category:** [sandbox|discovery|timeline|search|settings|etc.]
**Verified In:** [version or PR]

**Scenario:**
[What user action or system behavior needs testing]

**Manual QA Steps Performed:**
1. Step one
2. Step two
3. ...

**Fix Reference:**
[Commit hash, PR, or "new feature"]

**E2E Test Requirements:**
[What the test needs - fixtures, mocks, build type, etc.]

**Complexity:** [Low|Medium|High]
```
