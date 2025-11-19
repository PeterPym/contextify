# Operational Guides

How-to documentation for using, debugging, and extending Contextify.

## Phase 3 Updates (Nov 2025)

**New debugging areas:** AppStateOrchestrator state transitions, lazy loading flows
**Log prefixes:** `[ORCH-*]`, `[DISC-LIGHT]`, `[INGEST-JIT]`, `[BG-INDEX]`

## Purpose

This directory contains practical guides for:
- Developer workflows
- Debugging and diagnostics
- Build and CI processes
- Operational best practices

## Documents

### Debugging Toolkit
**Primary resource:** [`../../scripts/logging/README.md`](../../scripts/logging/README.md)
- Automated test harnesses with pass/fail validation
- Pipeline completeness checking
- Gap analysis for performance issues
- Interactive monitoring with color-coded output
- LLM-optimized dispatch table

### [Diagnostics API](diagnostics-api.md)
**Topics:** HTTP API for debugging (DEBUG builds only)
- Endpoints: `/health`, `/diagnostics`, `/timeline/recent`, `/timeline/latest`
- Entry fields and formats
- Use cases for debugging timeline state, hoover lag, LLM generation

### [Linux CI Builds](linux-ci-builds.md)
**Topics:** Building Contextify from non-macOS environments
- On-demand GitHub Actions with macOS runners
- Artifact downloads and result bundles
- Workflow features and troubleshooting

### [Logging Best Practices](logging-best-practices.md)
**Topics:** OSLog usage guidelines
- Log levels (debug, info, warning, error)
- Two-phase approach (development vs pre-merge)
- Privacy annotations and console filters
- Detailed code examples and anti-patterns

### [Log Analysis Methodology](log-analysis-methodology.md)
**Topics:** Systematic approach to validating system function using diagnostic logs
- Quick validation checklist (5 essential checks)
- Core tag reference with examples
- Measurement patterns (completion rate, sequence, timing, correlation)
- Common analysis workflows (feature not appearing, app slow, validate fix)
- Tag evolution tracking

### [Log Analysis Quick Reference](log-analysis-quick-reference.md)
**Topics:** One-page rapid troubleshooting guide
- 30-second health check
- Essential tags table
- Common diagnostics (one-liners)
- Decision tree for timeline issues
- Performance thresholds

### [Transcript Resumption](transcript-resumption.md)
**Topics:** Guide for resuming transcript ingestion
- HooverEngine checkpointing
- Manual checkpoint reset
- Recovery from incomplete ingestion

### [Timeline Diagnostics](timeline-diagnostics.md)
**Topics:** Timeline diagnostics framework
- HTTP endpoints for timeline inspection
- Integration with diagnostics API
- Real-time monitoring

### [Feature Flags](feature-flags.md)
**Topics:** Feature flag documentation
- Available flags and their purposes
- How to enable/disable features
- Developer mode flags

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
