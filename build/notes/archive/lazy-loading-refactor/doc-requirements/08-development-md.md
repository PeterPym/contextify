# Change Requirements: build/docs/guides/DEVELOPMENT.md

**Document:** `build/docs/guides/DEVELOPMENT.md`
**Priority:** 3 (User Guides)
**Impact:** Medium - Primary development guide
**Estimated Effort:** 1-2 hours

---

## Current State Analysis

**File:** Primary development guide with build commands and workflows
**Current Content:**
- Build commands
- Test running
- Development workflows
- Architecture overview

**Issues:**
1. Architecture overview outdated (doesn't mention AppStateOrchestrator)
2. No debugging tips for lazy loading
3. Performance expectations for tests outdated
4. No reference to Phase 3 architecture docs

---

## Required Changes

### 1. Update Architecture Overview Section

**Current:** Lists key components

**Add:**

```markdown
### Phase 3 Architecture (Nov 2025)

**Central Coordinator:**
- `AppStateOrchestrator` - State machine for app lifecycle
  - Location: `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`
  - Pattern: Singleton, @MainActor, state machine (AppState enum)

**Discovery Services:**
- `LightweightDiscoveryService` - Stat-only scanning (<200ms startup)
  - Location: `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`
  - Pattern: Actor, background execution
- `ProjectDiscoveryService` - Full ingestion (JIT, background)
  - Location: `app/Sources/ContextifyCore/Projects/ProjectDiscoveryService.swift`
  - Pattern: Actor, secondary to LightweightDiscoveryService

**View Models:**
- `ProjectsViewModel` - Observer pattern (simplified in Phase 3, -278 lines)
  - Location: `Contextify/Contextify/ProjectsViewModel.swift`
  - Pattern: @Observable, observes AppStateOrchestrator

**Legacy Components (Phase 4 deprecation):**
- `StartupCoordinator` - Compatibility shim for ConversationMonitor
  - Will be removed after ConversationMonitor refactor

**See Also:**
- `build/docs/architecture/COMPONENTS.md` - Complete architecture reference
- `build/docs/architecture/data-pipeline-architecture.md` - Data flow details
```

**Estimated Effort:** 20 minutes

---

### 2. Add Debugging Section for Lazy Loading

**Location:** Insert in debugging/troubleshooting section

**Content:**

```markdown
## Debugging Lazy Loading Issues (Phase 3)

### Common Issues

**1. Project Not Appearing in List**

**Symptom:** Project visible in filesystem but not in Contextify UI

**Debug Steps:**
```bash
# Check if LightweightDiscoveryService found it
tail -f ~/Library/Logs/Contextify/app.log | grep "DISC-LIGHT"
# Should see: [DISC-LIGHT] Scan complete in X.XXXs. Found N projects.

# Check project count
grep "Found.*projects" ~/Library/Logs/Contextify/app.log | tail -1
```

**Common Causes:**
- Project folder doesn't match expected pattern
- No `.jsonl` files in directory
- Permissions issue (sandbox builds)

**Fix:** Use manual "Refresh Projects" action to force re-scan

---

**2. JIT Ingestion Failures**

**Symptom:** Project appears in list but timeline stays blank

**Debug Steps:**
```bash
# Check orchestrator state transitions
tail -f ~/Library/Logs/Contextify/app.log | grep "ORCH-SELECT"
# Should see:
# [ORCH-SELECT] User selected project: <id>
# [ORCH-SELECT] Loading project: <name>
# [ORCH-SELECT] Project ready in X.XXXs

# Check for ingestion errors
grep "ORCH-SELECT.*Failed" ~/Library/Logs/Contextify/app.log
```

**Common Causes:**
- Database write failure
- JSONL parsing error
- Missing project in database

**Fix:** Check error logs for specific failure reason

---

**3. Background Indexing Stuck**

**Symptom:** Status bar shows "Indexing X/Y" forever

**Debug Steps:**
```bash
# Check background indexing progress
tail -f ~/Library/Logs/Contextify/app.log | grep "ORCH-BACKGROUND"
# Should see periodic progress updates

# Check for cancellation
grep "ORCH-BACKGROUND.*cancelled" ~/Library/Logs/Contextify/app.log
```

**Common Causes:**
- Task cancelled by user interaction
- Ingestion error on one project (loop broken)

**Fix:** Restart app to retry background indexing

---

### Log Patterns to Know

**Startup Flow:**
```
[ORCH-STARTUP] Beginning lightweight startup...
[DISC-LIGHT] Starting lightweight scan...
[DISC-LIGHT] Scan complete in 0.143s. Found 19 projects.
[ORCH-STARTUP] Startup complete in 0.187s. UI ready.
[ORCH-STARTUP] Auto-selecting most recent project: <id>
```

**Project Selection:**
```
[ORCH-SELECT] User selected project: <id>
[ORCH-SELECT] Loading project: <name>
[ORCH-SELECT] JIT ingestion complete, DB project ID: <id>
[ORCH-SELECT] StartupCoordinator notified with path: <path>
[ORCH-SELECT] Project ready in 0.856s
```

**Background Indexing:**
```
[ORCH-BACKGROUND] Starting background indexing...
[ORCH-BACKGROUND] Ingested project: <id>
[ORCH-BACKGROUND] Indexing cancelled  (if user interacts)
[ORCH-BACKGROUND] Background indexing complete
```
```

**Estimated Effort:** 30 minutes

---

### 3. Update Performance Expectations Section

**Add:**

```markdown
## Performance Expectations (Phase 3)

**Startup:**
- App launch to UI ready: <200ms (target), 143-187ms (typical)
- If slower: Check LightweightDiscoveryService logs for bottleneck

**Project Selection:**
- First selection (JIT ingestion): 500-1000ms
- Subsequent selections (already ingested): <100ms
- If slower: Check HooverEngine logs for parsing issues

**Memory:**
- At startup: 30-50 MB (Phase 3 baseline)
- After first project load: 60-100 MB
- Steady state: 80-150 MB (depends on active projects)
- If higher: Check for memory leaks (Instruments)

**Database:**
- At startup: 19 row updates (projects metadata)
- Per project JIT: 30-100 transcript rows + 500-5000 entry rows
- If slower: Check database location (network drives are slow)

**Build Performance:**
- Clean build: 15-30s (Xcode 16)
- Incremental: 2-5s
- Tests: 5-10s (unit), 30-60s (integration)
```

**Estimated Effort:** 15 minutes

---

### 4. Add Cross-References Section

**Location:** End of document

**Content:**

```markdown
## Phase 3 Architecture References

**Core Documentation:**
- Architecture overview: `build/docs/architecture/COMPONENTS.md`
- Data pipeline: `build/docs/architecture/data-pipeline-architecture.md`
- Refactoring analysis: `build/docs/architecture/architecture-refactoring-analysis.md`

**Implementation Guides:**
- Discovery services: `build/docs/components/project-discovery-service-implementation.md`
- Startup coordination: `build/docs/components/startup-coordinator-implementation.md`

**Debugging:**
- Log analysis: `build/docs/guides/log-analysis-methodology.md`
- Debugging workflows: `build/docs/guides/debugging-workflows.md`

**Testing:**
- Integration tests: `build/docs/testing/integration-testing-guide.md`
- Performance benchmarks: `build/docs/testing/performance-benchmarks.md`
```

**Estimated Effort:** 10 minutes

---

## Summary of Changes

1. **Update:** Architecture overview section (~40 lines)
2. **Add:** Debugging lazy loading section (~80 lines)
3. **Add:** Performance expectations (Phase 3) (~30 lines)
4. **Add:** Cross-references section (~20 lines)

**Total Lines Added/Modified:** ~170 lines
**Estimated Effort:** 1-2 hours

---

## Validation Checklist

After making changes, verify:

- [ ] AppStateOrchestrator listed in key components
- [ ] LightweightDiscoveryService documented
- [ ] Debugging steps accurate (tested against logs)
- [ ] Log patterns match actual log output
- [ ] Performance expectations validated
- [ ] Cross-references resolve correctly
- [ ] Build commands still accurate
- [ ] Test commands still work

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #8
