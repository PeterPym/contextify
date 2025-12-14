# Feature Development Workflow

This document defines the workflow for developing new features and significant refactors in Contextify.

## Overview

```
Problem Statement → Technical Specification → Implementation Plan → Implementation → Review
```

Each phase has clear deliverables and gates before proceeding.

## When to Use This Workflow

**Required for:**
- New user-facing features
- Significant refactors affecting multiple components
- Changes to core data flows (ingestion, search, timeline)
- Anything touching the database schema

**Optional for:**
- Bug fixes (unless complex)
- Documentation updates
- Minor UI tweaks
- Performance optimizations (unless architectural)

## Phase 1: Problem Statement

Before writing code, clearly define the problem.

**Deliverable:** Brief written statement (can be in TODOS.md, GitHub issue, or chat)

**Contents:**
- What problem are we solving?
- Who is affected?
- What does success look like?

**Example:**
> Users can't find old conversations easily. Need full-text search across all transcripts with result highlighting.

## Phase 2: Technical Specification

A structured document that defines the solution before implementation.

**Location:** `build/notes/specs/` or `/tmp/` for drafts

**Template:**

```markdown
# Feature: [Name]

## Problem Statement
[From Phase 1]

## Proposed Solution
[High-level approach]

## User Experience
- How does the user interact with this feature?
- What UI changes are needed?
- What keyboard shortcuts (if any)?

## Technical Design

### Components Affected
- [ ] List each file/module that needs changes

### Data Model Changes
- Schema migrations needed?
- New tables/columns?

### Architecture Decisions
- Why this approach over alternatives?
- Trade-offs accepted?

### macOS Compatibility
- Does this feature require macOS 26+ (Apple Intelligence)?
- Is fallback behavior defined for Lite Mode (macOS 15)?
- Are `#available(macOS 26, *)` guards needed?
- Does `LLMAvailability.current.isLiteMode` need to gate any functionality?

## Test Requirements

### Unit Tests
- [ ] List specific unit tests to add
- [ ] What edge cases need coverage?

### E2E Tests
- [ ] New QA test needed? Which user flow?
- [ ] Existing QA tests need updates?
- [ ] Test contract requirements (isolation, database state)
- [ ] Log tags needed for assertions? (e.g., `[FEATURE-INIT]`, `[FEATURE-DONE]`)

### Manual Testing
- [ ] What needs manual verification?
- [ ] Is a small QA script useful for repeatability?
  - If yes, keep it alongside the spec/plan while the work is active so it archives with the supporting docs.
  - Example: `build/notes/todo-support/CONTEXT-REINJECTION-qa-runner.sh`

## Rollout Considerations
- Feature flag needed?
- Migration path for existing users?
- Documentation updates required?

## Open Questions
- [ ] Unresolved decisions that need input
```

**Gate:** Spec reviewed and questions resolved before proceeding.

## Phase 3: Implementation Plan

Break the spec into ordered, atomic tasks.

**Location:** Can be in the spec doc or a separate plan file

**Format:**
```markdown
## Implementation Plan

### Phase 1: Foundation
- [ ] Task 1 (commit: "feat(search): add FTS5 table")
- [ ] Task 2

### Phase 2: Core Logic
- [ ] Task 3
- [ ] Task 4

### Phase 3: UI
- [ ] Task 5

### Phase 4: Tests
- [ ] Add unit tests for X
- [ ] Add/update E2E test QA-XX
```

**Rules:**
- Each task = one atomic commit
- Tests are explicit tasks, not afterthoughts
- Order tasks to enable incremental testing

## Phase 4: Implementation

Execute the plan, committing atomically.

**Rules:**
- Follow the plan order
- Update TODOS.md as you go
- If plan needs changing, update it first
- Run `swift test` before each commit
- Run `bash scripts/xc.sh build` (zero warnings)

## Phase 5: Review

Before merging to main, complete the pre-merge checklist.

**Quick validation:**
```bash
swift test                    # Unit tests pass
bash scripts/xc.sh build      # Zero warnings
```

**Full checklist:** See `pre-merge-checklist.md` for comprehensive guidance on:
- E2E testing requirements
- Documentation audit
- TODOS.md administration (removing items, archiving support docs)
- Technical debt tracking

**Minimum checklist:**
- [ ] All planned tasks complete
- [ ] Unit tests written and passing
- [ ] E2E tests added/updated as specified
- [ ] Build has zero warnings
- [ ] TODOS.md updated (items removed/added)
- [ ] Support docs archived to `build/docs/archive/completed-work/`

## E2E Test Requirements

### When to Add New E2E Tests

Add a new QA test (`scripts/qa/tests/QA-XX-*.sh`) when:
- New user flow is introduced (e.g., new window, new search mode)
- Critical path changes significantly
- Complex multi-step interaction is added

### When to Update Existing E2E Tests

Update existing QA tests when:
- UI flow changes (keyboard shortcuts, button locations)
- Expected log patterns change
- Database schema changes affect test assertions
- New assertions needed for expanded functionality

### E2E Test Contracts

Every E2E test must have a `@test_contract` header defining:
- Isolation requirements (transcript backup, database state)
- Database preconditions and mutations
- Dependencies on other tests

See `scripts/qa/README.md` for full details.

## Quick Reference

| Phase | Deliverable | Gate |
|-------|-------------|------|
| Problem | Written statement | Clear understanding |
| Spec | Technical specification | Questions resolved |
| Plan | Ordered task list | Tasks are atomic |
| Implement | Code + tests | Tests pass, zero warnings |
| Review | Checklist complete | Ready to merge |
