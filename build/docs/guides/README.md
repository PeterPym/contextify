# Operational Guides

**Status:** Updated for Phase 3 lazy loading architecture (Nov 2025)

**Phase 3 Debugging:** See [debugging-workflows.md](debugging-workflows.md) - "Phase 3 Debugging" section

---

How-to documentation for using, debugging, and extending Contextify.

## Key Debugging Areas

**Focus areas:** AppStateOrchestrator state transitions, lazy loading flows
**Log prefixes:** `[ORCH-*]`, `[DISC-LIGHT]`, `[INGEST-JIT]`, `[BG-INDEX]`

## Purpose

This directory contains practical guides for:
- Developer workflows
- Debugging and diagnostics
- Build and CI processes
- Operational best practices

## Development

### [DEVELOPMENT.md](DEVELOPMENT.md)
**Topics:** Build commands, workflows, and development setup
- **✨ Updated for Phase 3:** Architecture overview, debugging lazy loading, performance expectations
- Quick build, test, clean commands
- Database management
- Pre-commit hooks

---

## Debugging

### Debugging Toolkit
**Primary resource:** [`../../scripts/logging/README.md`](../../scripts/logging/README.md)
- Automated test harnesses with pass/fail validation
- Pipeline completeness checking
- Gap analysis for performance issues
- Interactive monitoring with color-coded output
- LLM-optimized dispatch table

### [Debugging Workflows](debugging-workflows.md)
**Topics:** Decision trees and systematic troubleshooting
- **✨ Updated for Phase 3:** Lazy loading issues, AppStateOrchestrator state transitions, JIT ingestion debugging
- 7 comprehensive workflows (pipeline check, performance, state sync, database, sandbox, bug verification, custom investigation)
- Automated tool recommendations

### [Log Analysis Methodology](log-analysis-methodology.md)
**Topics:** Systematic approach to validating system function using diagnostic logs
- **✨ Updated for Phase 3:** [ORCH-*] and [DISC-LIGHT] prefixes, state machine log examples
- Quick validation checklist (5 essential checks)
- Core tag reference with examples
- Measurement patterns (completion rate, sequence, timing, correlation)
- Common analysis workflows

### [Log Analysis Quick Reference](log-analysis-quick-reference.md)
**Topics:** One-page rapid troubleshooting guide
- 30-second health check
- Essential tags table
- Common diagnostics (one-liners)
- Decision tree for timeline issues

### [Logging Best Practices](logging-best-practices.md)
**Topics:** OSLog usage guidelines
- Log levels (debug, info, warning, error)
- Two-phase approach (development vs pre-merge)
- Privacy annotations and console filters
- Consider updating for Phase 3 categories

### [Diagnostics API](diagnostics-api.md)
**Topics:** HTTP API for debugging (DEBUG builds only)
- Endpoints: `/health`, `/diagnostics`, `/timeline/recent`, `/timeline/latest`
- Entry fields and formats
- Unchanged in Phase 3

### [Timeline Diagnostics](timeline-diagnostics.md)
**Topics:** Timeline diagnostics framework
- HTTP endpoints for timeline inspection
- Integration with diagnostics API
- Unchanged in Phase 3

---

## Transcript Analysis

### [TRANSCRIPT-ANALYSIS.md](TRANSCRIPT-ANALYSIS.md)
**Topics:** Workflow for analyzing and classifying transcript formats
- Format detection
- Provider identification
- Unchanged in Phase 3

### [Transcript Resumption](transcript-resumption.md)
**Topics:** Guide for resuming transcript ingestion
- HooverEngine checkpointing
- Manual checkpoint reset
- Recovery from incomplete ingestion
- Unchanged in Phase 3

---

## Operations

### [Security-Scoped Bookmarks](security-scoped-bookmarks.md)
**Topics:** Bookmark management for App Store builds
- Bookmark lifecycle
- Permission grants
- Unchanged in Phase 3

### [Feature Flags](feature-flags.md)
**Topics:** Feature flag documentation
- Available flags and their purposes
- How to enable/disable features
- Unchanged in Phase 3

### [Linux CI Builds](linux-ci-builds.md)
**Topics:** Building Contextify from non-macOS environments
- On-demand GitHub Actions with macOS runners
- Artifact downloads and result bundles
- Unchanged in Phase 3

---

## Quick Reference (Phase 3)

**Slow Startup?**
→ [debugging-workflows.md](debugging-workflows.md) - "Debugging Lazy Loading Issues"
→ [log-analysis-methodology.md](log-analysis-methodology.md) - Check [DISC-LIGHT] logs

**Project Not Appearing?**
→ [debugging-workflows.md](debugging-workflows.md) - "Feature Not Appearing"
→ Check discovery count vs filesystem

**Timeline Blank?**
→ [debugging-workflows.md](debugging-workflows.md) - "Workflow 2: Performance Investigation"
→ Check [ORCH-SELECT] logs for JIT ingestion errors

**Background Indexing Stuck?**
→ [debugging-workflows.md](debugging-workflows.md) - "Workflow 3: State Management Debugging"
→ Check [BG-INDEX] logs

---

## Related Documentation

**Architecture:**
- [../architecture/COMPONENTS.md](../architecture/COMPONENTS.md) - AppStateOrchestrator, LightweightDiscoveryService
- [../architecture/data-pipeline-architecture.md](../architecture/data-pipeline-architecture.md) - Data flow with lazy loading

**Components:**
- [../components/project-discovery-service-implementation.md](../components/project-discovery-service-implementation.md) - Two-tier discovery
- [../components/startup-coordinator-implementation.md](../components/startup-coordinator-implementation.md) - Legacy integration

**Testing:**
- [../testing/integration-testing-guide.md](../testing/integration-testing-guide.md) - Phase 3 testing patterns (TBD)
- [../testing/performance-benchmarks.md](../testing/performance-benchmarks.md) - Phase 3 validated metrics (TBD)

---

## Relationship to Other Docs

- **Architecture/** - Systems described in guides (SQL backend, LLM processing, etc.)
- **Components/** - Components used by these guides (HooverEngine, diagnostics endpoints, etc.)
- **Operations/** - Related to deployment and release processes

---

## Updating These Docs

**When to update:**
- After adding new diagnostic endpoints or tools
- When build/CI processes change
- When best practices evolve based on experience

**What to include:**
- Step-by-step instructions
- Command examples with expected output
- Troubleshooting tips for common issues
- Links to relevant code or other docs

**What NOT to include:**
- Implementation plans (use /tmp/)
- Feature proposals (use /tmp/ or TODOS.md)
- Bug reports (use GitHub issues or TODOS.md)
