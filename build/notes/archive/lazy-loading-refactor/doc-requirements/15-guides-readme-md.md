# Change Requirements: build/docs/guides/README.md

**Document:** `build/docs/guides/README.md`
**Priority:** 5 (READMEs)
**Impact:** Low - Guides directory index
**Estimated Effort:** 30 minutes

---

## Current State Analysis

**File:** Directory index listing guide documents
**Current Content:**
- Lists guide docs with brief descriptions

**Issues:**
1. Descriptions don't mention Phase 3 updates
2. No guidance on Phase 3-specific debugging
3. No cross-references to Phase 3 architecture

---

## Required Changes

### 1. Add Phase 3 Note at Top

```markdown
# Guides Documentation

**Status:** Updated for Phase 3 lazy loading architecture (Nov 2025)

**Phase 3 Debugging:** See `debugging-workflows.md` - "Debugging Lazy Loading Issues"

---
```

### 2. Update Guide Descriptions

```markdown
## Development

**DEVELOPMENT.md** - Build commands, workflows, and development setup
- **Updated for Phase 3:** Architecture overview, debugging lazy loading, performance expectations

---

## Debugging

**debugging-workflows.md** - Comprehensive debugging guide
- **Updated for Phase 3:** Lazy loading issues, AppStateOrchestrator state transitions, troubleshooting flowcharts

**log-analysis-methodology.md** - Log analysis strategies and patterns
- **Updated for Phase 3:** [ORCH-*] and [DISC-LIGHT] prefixes, state machine log examples

**log-analysis-quick-reference.md** - One-page troubleshooting guide
- Consider updating for Phase 3 (not in master list)

**diagnostics-api.md** - Timeline diagnostics API
- Unchanged in Phase 3

**timeline-diagnostics.md** - Timeline-specific debugging
- Unchanged in Phase 3

---

## Transcript Analysis

**TRANSCRIPT-ANALYSIS.md** - Workflow for analyzing transcript formats
- Unchanged in Phase 3

**transcript-resumption.md** - Resuming interrupted transcripts
- Unchanged in Phase 3

---

## Operations

**security-scoped-bookmarks.md** - Security-scoped bookmark management (App Store builds)
- Unchanged in Phase 3

**feature-flags.md** - Feature flag system
- Unchanged in Phase 3

**linux-ci-builds.md** - GitHub Actions CI/CD for Linux builds
- Unchanged in Phase 3

---

## Best Practices

**logging-best-practices.md** - OSLog conventions and privacy
- **Consider updating** for Phase 3 categories (AppOrchestrator, LightweightDiscovery)

---
```

### 3. Add Quick Reference Section

```markdown
## Quick Reference (Phase 3)

**Slow Startup?**
→ `debugging-workflows.md` - "Debugging Lazy Loading Issues"
→ `log-analysis-methodology.md` - Check [DISC-LIGHT] logs

**Project Not Appearing?**
→ `debugging-workflows.md` - "Issue: Projects Not Appearing"
→ Check discovery count vs filesystem

**Timeline Blank?**
→ `debugging-workflows.md` - "Issue: JIT Ingestion Hangs"
→ Check [ORCH-SELECT] logs for errors

**Background Indexing Stuck?**
→ `debugging-workflows.md` - "Issue: Background Indexing Never Completes"
→ Check [ORCH-BACKGROUND] logs

---
```

### 4. Add Cross-References Section

```markdown
## Related Documentation

**Architecture:**
- `../architecture/COMPONENTS.md` - AppStateOrchestrator, LightweightDiscoveryService
- `../architecture/data-pipeline-architecture.md` - Data flow with lazy loading

**Testing:**
- `../testing/integration-testing-guide.md` - Phase 3 testing patterns
- `../testing/performance-benchmarks.md` - Phase 3 validated metrics

---
```

**Estimated Effort:** 30 minutes

---

## Summary of Changes

1. **Add:** Phase 3 status note (~5 lines)
2. **Update:** Guide descriptions (Phase 3 notes) (~15 lines modified)
3. **Add:** Quick reference section (~20 lines)
4. **Add:** Cross-references section (~12 lines)

**Total Lines Added/Modified:** ~52 lines
**Estimated Effort:** 30 minutes

---

## Validation Checklist

After making changes, verify:

- [ ] All referenced files exist
- [ ] Phase 3 notes accurate
- [ ] Quick reference helpful
- [ ] Cross-references resolve
- [ ] Guide descriptions match actual content

---

**Document Version:** 1.0
**Created:** 2025-11-19
**Implements:** Phase 3 documentation update item #15
