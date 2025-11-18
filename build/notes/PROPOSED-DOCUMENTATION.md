# Proposed New Documentation

**Date:** 2025-11-17
**Purpose:** Track missing documentation identified during systematic code audit

This document catalogs documentation gaps discovered during the comprehensive audit of `build/docs/`. Each proposal includes justification and scope.

---

## Priority 1: Critical Missing Documentation

### 1. ✅ Complete Data Pipeline Architecture (CREATED 2025-11-17)

**Created Path:** `build/docs/architecture/data-pipeline-architecture.md` (1083 lines)

**Justification:**
The current `data-flow.md` provides high-level overview but lacks the nitty-gritty implementation details needed for debugging and extending the system. Recent changes (fast path, coordinator integration, Codex global discovery) have created complexity that isn't fully documented.

**Scope:**
- **Fast Path Discovery (Phase 2)**
  - How `StartupCoordinator` scans `~/.claude/projects` and `~/.codex/sessions/YYYY/MM/DD/*.jsonl`
  - mtime-based "newest transcript" selection logic
  - Preview ingestion (first 25 entries) vs full ingestion
  - Code path: `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`

- **Full Discovery (Phase 3)**
  - `ProjectDiscoveryService` deep scan implementation
  - Claude Code: directory-based discovery
  - Codex CLI: global `~/.codex/sessions` tree with legacy `<repo>/.codex/sessions` fallback
  - Code path: Component to be identified

- **HooverEngine Streaming Ingestion**
  - Batch processing (1000 rows at a time)
  - Crash-safe checkpointing (`last_processed_line`, `last_processed_entry_id`)
  - Parse error isolation (bad lines don't block ingestion)
  - Window tracking (prev1/prev2) for LLM context
  - CTE-based FK-safe assistant_usage reconciliation
  - Code path: `app/Sources/ContextifyCore/Database/HooverEngine.swift`

- **TranscriptWatcher Real-Time Monitoring**
  - DispatchSource file system monitoring
  - Incremental ingestion triggers
  - Debouncing and rate limiting
  - Code path: `app/Sources/ContextifyCore/Database/TranscriptWatcher.swift`

- **Database Persistence**
  - Transaction boundaries
  - WAL mode concurrent reads
  - Denormalized `project_id` in entries (performance optimization)
  - Code path: `app/Sources/ContextifyCore/Database/`

**Mermaid Diagrams Needed:**
1. Startup sequence (cold start → fast path → full discovery → persistence)
2. HooverEngine streaming batch processing flow
3. TranscriptWatcher event handling
4. Database transaction boundaries and isolation

**Known Technical Debt to Document:**
- Duplicate initialization paths in ConversationMonitor (see `conversation-monitor-state.md`)
- Legacy `<repo>/.codex/sessions` fallback (should be deprecated?)
- Fast path mtime comparison assumes filesystem timestamps are reliable
- No validation that "newest transcript" belongs to current project
- HooverEngine batch size (1000) not tunable
- Parse errors silently logged but not surfaced to user

---

### 2. ✅ Architecture Deep Dive & Refactoring Opportunities (CREATED 2025-11-17)

**Created Path:** `build/docs/architecture/architecture-refactoring-analysis.md` (1543 lines)

**Justification:**
The codebase has evolved organically with tactical fixes. A comprehensive refactoring analysis would identify:
- Structural debt (overlapping responsibilities, tight coupling)
- Performance bottlenecks (N+1 queries, excessive MainActor hopping)
- Testability issues (hard-to-mock singletons, hidden state)
- Opportunities for simplification

**Scope:**
- **Actor Isolation Audit**
  - Current `@MainActor` usage patterns
  - Unnecessary main thread blocking
  - Opportunities to move work off main thread
  - Code paths: All `@MainActor` classes in `Contextify/Contextify/`

- **State Management Analysis**
  - Observable vs @StateObject usage
  - Derived state computation (cached vs recomputed)
  - Source of truth violations (duplicate state)
  - Code paths: `ConversationMonitor.swift`, `ProjectSwitcherState.swift`, `HUDViewModel.swift`

- **Database Layer Refactoring**
  - Repository pattern consistency
  - TranscriptOrchestrator vs direct repository access
  - Query optimization opportunities
  - Schema normalization opportunities (current: only project_id denormalized)
  - Code paths: `app/Sources/ContextifyCore/Database/`

- **Coordinator vs Orchestrator vs Monitor**
  - Role clarity and separation of concerns
  - Overlapping responsibilities
  - Initialization coupling
  - Code paths: `StartupCoordinator.swift`, `TranscriptOrchestrator.swift`, `ConversationMonitor.swift`

- **LLM Queue Consolidation**
  - Abstract queue design (already documented in `abstract-llm-queue-design.md`)
  - Implementation blockers
  - Migration path
  - Code paths: `TimelineCacheMissGenerator.swift`, `TranscriptMetadataOrchestrator.swift`

**Refactoring Opportunities:**
1. **Extract ProjectContext as first-class type** (reduce `currentProjectId: String` passing)
2. **Consolidate initialization paths** (single source of truth for startup)
3. **Move database queries off main thread** (even GRDB reads can block UI)
4. **Replace singleton DatabaseManager with dependency injection** (improve testability)
5. **Create unified transcript source abstraction** (Claude Code vs Codex CLI discovery)
6. **Separate read models from write models** (CQRS pattern for complex queries)

---

## Priority 2: Component Deep Dives

### 3. ✅ StartupCoordinator Complete Implementation Guide (CREATED 2025-11-17)

**Created Path:** `build/docs/components/startup-coordinator-implementation.md` (881 lines)

**Justification:**
`build/docs/architecture/startup-coordinator.md` describes the design but lacks implementation details needed for debugging race conditions and understanding initialization order.

**Scope:**
- AsyncStream-based publish/subscribe pattern
- Sequencing guarantees (what happens if events arrive out of order?)
- Error handling and recovery
- Testing strategy
- Code verification against: `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift`

---

### 4. ✅ ProjectDiscoveryService Implementation (CREATED 2025-11-17)

**Created Path:** `build/docs/components/project-discovery-service-implementation.md` (969 lines)

**Justification:**
Currently only high-level description exists. Need detailed implementation for:
- Multi-provider scanning (Claude Code + Codex CLI)
- Deduplication logic (same project discovered via multiple paths)
- Security-scoped bookmark integration
- Performance characteristics (scanning 100+ projects)
- Code path: TBD (need to find actual implementation)

---

### 5. ✅ Timeline Cache Invalidation Strategy (CREATED 2025-11-17)

**Created Path:** `build/docs/components/timeline-cache-invalidation.md` (803 lines)

**Justification:**
`timeline-cache.md` documents caching but not invalidation. Need to document:
- When cache entries are evicted (never? or on content change?)
- How content+window hash changes trigger regeneration
- Handling of schema version changes in `generator_signature`
- Migration path when LLM prompt changes
- Code verification against: `TimelineCacheMissGenerator.swift`, database schema

---

## Priority 3: Operational Guides

### 6. ✅ Codebase Health Audit (COVERED 2025-11-17)

**Covered By:** `build/docs/architecture/architecture-refactoring-analysis.md` (Doc #2)

**Justification:**
The architecture refactoring analysis document (Doc #2) comprehensively covers all aspects of codebase health:
- File size analysis with god object identification (ConversationMonitor 3054 lines, HUDCore 1196 lines, ProjectDiscoveryService 1000 lines)
- Module structure and boundaries (coupling analysis, dependency graphs)
- Swift best practices compliance (concurrency patterns, testability ~15-20% coverage)
- Architecture patterns (coordinator/orchestrator/monitor analysis)
- Code organization (directory structure, separation of concerns)
- Refactoring recommendations with priority ordering (P0-P3) and 4-phase migration roadmap

**Note:** Creating a separate codebase health audit document would be redundant given the comprehensive coverage in architecture-refactoring-analysis.md.

---

### 7. ✅ Database Migration Runbook (CREATED 2025-11-17)

**Created Path:** `build/docs/operations/database-migration-runbook.md` (675 lines)

**Justification:**
`database-migration.md` documents the component but not the operational procedure. This runbook provides:
- Step-by-step migration procedure for users (UI and CLI methods)
- Rollback procedures (failed migration, accidental deletion)
- Backup/restore process with launchd scheduling
- Multi-machine conflict resolution (sequential access, separate DBs)
- Troubleshooting guide (6 common issues with symptoms/cause/resolution)
- Code verification against: DatabaseMigration.swift (155 lines), DatabaseManager.swift (WAL mode)

---

### 8. ✅ Debugging Workflow Guide (CREATED 2025-11-17)

**Created Path:** `build/docs/guides/debugging-workflows.md` (747 lines)

**Justification:**
Multiple debugging docs exist (`diagnostics-api.md`, `timeline-diagnostics.md`, `log-analysis-*`) but no unified workflow guide. This document provides:
- Quick decision tree (7 issue types with diagnostic routing)
- Workflow 1-7 (pipeline completeness, performance, state, database, sandbox, testing, exploratory)
- Tool selection matrix (when to use logs vs diagnostics API vs database inspection)
- Diagnostic API reference (endpoints, payloads, interpretation)
- Common issues quick reference
- Ties together entire logging toolkit and debugging documentation

---

### 9. ✅ Security-Scoped Bookmark Patterns (CREATED 2025-11-17)

**Created Path:** `build/docs/guides/security-scoped-bookmarks.md` (697 lines)

**Justification:**
`transcript-access-security.md` documents architecture but not practical usage patterns. This guide provides:
- Decision tree for when to use scoped access
- Pattern 1: Protocol-based provider (recommended - TranscriptAccessProvider)
- Pattern 2: Direct bookmark management (legacy/special cases)
- Pattern 3: Actor-based async access (future concurrency model)
- Common pitfalls with fixes (4 anti-patterns: forgotten stop, nested access, stale bookmarks, wrong scope)
- Performance implications (bookmark resolution cost, access nesting overhead)
- Testing strategies (sandbox vs DMG builds, permission simulation)
- Troubleshooting guide (authorization failures, stale bookmarks)

---

## Priority 4: Testing & Quality

### 10. ✅ Integration Testing Strategy (CREATED 2025-11-17)

**Created Path:** `build/docs/testing/integration-testing-guide.md` (969 lines)

**Justification:**
Only `first-run-qa-guide.md` exists for testing. This comprehensive guide documents:
- Database integration tests (DatabaseTests.swift: 835 lines - schema, repositories, migrations, denormalization)
- Transcript ingestion tests (IntegrationTests.swift: 268 lines - HooverEngine workflow, crash recovery)
- LLM integration tests (FoundationLLMTests.swift: 549 lines - formatting, grounding, user intent, benchmarks)
- UI integration tests (ContextifyUITests.swift - basic tests, launch performance)
- Fixture management strategies (programmatic mocks vs fixture files)
- Test isolation and cleanup patterns (unique temp dirs, async cleanup)
- Performance testing with XCTest metrics (XCTClockMetric, XCTCPUMetric, XCTMemoryMetric)
- CI/CD integration (GitHub Actions, parallel testing, code coverage)
- Troubleshooting guide (5 common test failures with fixes)
- Code verification: Verified against all 13 test files (DatabaseTests.swift, IntegrationTests.swift, FoundationLLMTests.swift, etc.)

---

### 11. Performance Testing & Benchmarks

**Proposed Path:** `build/docs/testing/performance-benchmarks.md`

**Justification:**
Performance targets mentioned in various docs but no consolidated benchmarks. Need:
- Current performance baselines (database queries, LLM latency, UI frame rate)
- Regression testing strategy
- Profiling workflows (Instruments, XCTest performance tests)
- Known performance bottlenecks
- Code verification: Measure actual performance

---

## Priority 5: Design Documentation

### 12. SwiftUI Architecture Patterns

**Proposed Path:** `build/docs/design/swiftui-patterns.md`

**Justification:**
Inconsistent patterns across codebase. Need to document:
- When to use `@Observable` vs `@StateObject` vs `@State`
- View composition patterns
- Environment object patterns
- MainActor usage in SwiftUI
- Code verification: Survey all Views and ViewModels

---

### 13. Error Handling Philosophy

**Proposed Path:** `build/docs/design/error-handling-philosophy.md`

**Justification:**
Mixed error handling approaches (throws vs Result vs optional). Need:
- When to throw vs return Result
- User-facing error messages vs debug information
- Recovery strategies
- Logging conventions for errors
- Code verification: Survey error types and handling patterns

---

## Summary Statistics

**Total Proposed Documents:** 13
**Completed:** 9 (Priority 1: 2, Priority 2: 3, Priority 3: 3, Priority 4: 1)
**Remaining:** 4 (Priority 4: 1, Priority 5: 2)

**By Priority:**
- **Priority 1 (Critical):** 2/2 ✅ COMPLETE
- **Priority 2 (Component Deep Dives):** 3/3 ✅ COMPLETE
- **Priority 3 (Operational):** 3/3 ✅ COMPLETE (Doc #6 covered by architecture-refactoring-analysis.md)
- **Priority 4 (Testing):** 1/2 ⏳ IN PROGRESS
- **Priority 5 (Design):** 0/2 ⏳ PENDING

**Estimated Effort:**
- Priority 1: 16-24 hours (highly detailed, mermaid diagrams, code analysis)
- Priority 2: 8-12 hours
- Priority 3: 6-10 hours
- Priority 4: 6-8 hours
- Priority 5: 4-6 hours

**Total:** 40-60 hours of documentation work

---

## Next Steps

1. Get approval on Priority 1 proposals (data pipeline + refactoring analysis)
2. Create detailed outlines for approved proposals
3. Conduct code analysis to gather implementation details
4. Draft documents with mermaid diagrams
5. Review with domain experts
6. Publish to `build/docs/`
