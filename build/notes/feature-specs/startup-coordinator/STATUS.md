# Startup Coordinator Refactor - Status

**Last Updated:** 2025-11-04
**Status:** Not Started (Tactical Fixes Merged First)
**Branch:** `fix/timeline-startup-races` (merged) → Future: `feat/startup-coordinator`

---

## What Was Done (Tactical Fixes)

The `fix/timeline-startup-races` branch addressed **P0 issues** from the implementation plan using tactical fixes rather than the full architectural refactor:

### Completed Fixes
- ✅ **P0-1**: Stable projectId passing (`ConversationMonitor.startMonitoring(projectId:)`)
- ✅ **P0-2**: Deterministic startup (notification handshake, removed async deferrals)
- ✅ **P0-3**: Timeline deadlock prevention (verify `isMonitoring` before `isActive`)
- ✅ **P0-4**: Switcher promotion gap (`handleProjectRootChange` calls `getOrCreateProject`)
- ✅ **Critical**: Thread safety (TranscriptWatcher dictionary synchronization)
- ✅ **Medium**: Nonce-based suppression (replaced time-window with deterministic nonces)
- ✅ **Logging**: Privacy audit (made operational errors debuggable)

### Why These Were Valuable
- Eliminated crashes and races in production **immediately**
- Made codebase stable while planning architectural refactor
- Provide foundation for StartupCoordinator to build upon
- No throwaway work - fixes address real bugs independent of architecture

---

## What Remains (Architectural Refactor)

The full `StartupCoordinator` implementation from `implementation-plan.md` is still pending. This will provide:

### Core Components (Not Yet Implemented)
1. **`ActiveProjectContext`** model - Single source of truth for project identity
2. **`StartupCoordinator`** actor - Orchestrates startup sequencing
3. **AsyncStream coordination** - Replace NotificationCenter with typed streams
4. **Deterministic ordering** - Guarantee subsystems start in correct sequence

### Benefits Over Current Tactical Fixes
While the tactical fixes eliminated the most critical races, the architectural refactor provides:

- **Single source of truth**: No more "HUD path vs Switcher ID vs Monitor recomputation"
- **Explicit dependencies**: AsyncStream makes startup ordering visible and testable
- **Better testability**: Coordinator can be mocked, startup sequences unit tested
- **Foundation for features**: Multi-window support, project templates, etc.
- **Reduced complexity**: Eliminates notification timing dependencies and suppression logic

### Why Not Do This First?
- Tactical fixes provided **immediate stability** (crashes, deadlocks fixed now)
- Architectural refactor is **20-28 hours** of work (2.5-3.5 dev days)
- Incremental approach **reduces risk** (working state at each merge)
- Tactical fixes **inform** the refactor (we now know which parts are most fragile)

---

## Implementation Plan

See `implementation-plan.md` in this directory for complete 5-phase plan:
1. **Foundation** (4-6 hours) - Create `ActiveProjectContext` + `StartupCoordinator`
2. **Integration** (6-8 hours) - Rewire call sites to use coordinator
3. **Cleanup** (2-3 hours) - Remove legacy patterns
4. **Testing** (6-8 hours) - Unit tests + integration tests + manual runbook
5. **Documentation** (2-3 hours) - Architecture docs + AGENTS.md updates

---

## Next Steps

1. ✅ Merge `fix/timeline-startup-races` to main (tactical fixes)
2. ✅ Merge `fix/system-messages-display` to main (separate concern)
3. ⏸️ **Monitor production** for 1-2 weeks to validate tactical fixes
4. 🔜 Create `feat/startup-coordinator` branch
5. 🔜 Implement Phase 1 (Foundation) - `ActiveProjectContext` + `StartupCoordinator`
6. 🔜 Follow implementation plan through Phase 5

---

## References

- **Implementation Plan**: `./implementation-plan.md`
- **Current File States**: `/private/tmp/startup-coordinator-current-files.md` (snapshot)
- **Tactical Fixes Branch**: `fix/timeline-startup-races` (21 commits)
- **Related Docs**:
  - `build/notes/technical-reference/sql-backend-architecture.md`
  - `build/notes/technical-reference/conversation-monitor-state-architecture.md`
