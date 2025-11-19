# Component Documentation

**Status:** Updated for Phase 3 lazy loading architecture (Nov 2025)

**New in Phase 3:**
- AppStateOrchestrator (see `../architecture/COMPONENTS.md` - "Application State Coordination")
- LightweightDiscoveryService (two-tier discovery pattern)

---

Component-specific implementation details for Contextify's individual subsystems.

## Component Categories

**Current:** AppStateOrchestrator, LightweightDiscoveryService, FastPathIngestionCoordinator
**Legacy:** StartupCoordinator (compatibility shim, planned for refactor)

## Purpose

This directory contains focused documentation on specific components:
- How they work internally
- APIs and integration points
- Configuration and usage patterns
- Performance characteristics

### [Project Discovery](project-discovery.md)
**Component:** ConversationSources + Discovery Services
**Topics:** Multi-project detection and monitoring
- **✨ Phase 3:** Two-tier architecture (lightweight + full discovery)
- Provider-specific scanners (Claude Code, Codex CLI)
- FSEvents-based file watching
- Worktree support

### [Project Discovery Service Implementation](project-discovery-service-implementation.md)
**Components:** LightweightDiscoveryService + ProjectDiscoveryService
**Topics:** Implementation guide for discovery services
- **✨ Phase 3:** Two-tier discovery patterns
- **Tier 1:** LightweightDiscoveryService (stat-only scanning, <200ms)
- **Tier 2:** ProjectDiscoveryService (full ingestion, JIT)
- Security-scoped access patterns

### [Startup Coordinator Implementation](startup-coordinator-implementation.md)
**Component:** StartupCoordinator
**Topics:** Startup coordination and project identity
- **⚠️ Phase 3 Note:** StartupCoordinator now legacy compatibility shim
- Integration with AppStateOrchestrator
- handleExternalProjectSwitch() patterns
- See AppStateOrchestrator for new architecture

---

## State Management

### [Active Session Policy](active-session-policy.md)
**Component:** ActiveSessionPolicyEngine
**Topics:** Timeline follow behavior (automatic vs manual pin)
- Policy engine decision logic
- Follow mode persistence (schema v23)
- Switch reasons and notifications
- User-visible pin/unpin behavior
- Unchanged in Phase 3

### [Timeline Cache](timeline-cache.md)
**Component:** TimelineCacheMissGenerator + TranscriptMetadataOrchestrator
**Topics:** LLM-generated summary caching
- Cache keys (content + window SHA256)
- Miss detection and batch generation
- Integration with FoundationLLM
- Unchanged in Phase 3 (ConversationMonitor not refactored)

### [Timeline Cache Invalidation](timeline-cache-invalidation.md)
**Topics:** Cache invalidation strategies and edge cases
- Invalidation triggers
- Partial vs full invalidation
- Unchanged in Phase 3

---

## Data Layer

### [Database Migration](database-migration.md)
**Component:** DatabaseMigration
**Topics:** Custom database location and migration system
- Atomic migration with validation
- Security-scoped bookmarks for sandbox
- Multi-machine conflict detection
- Dropbox/iCloud sync support
- Unchanged in Phase 3

### [Transcript Ingestion](transcript-ingestion.md)
**Component:** HooverEngine
**Topics:** Streaming JSONL parser for transcript files
- Batch processing and checkpointing
- Window tracking
- Crash-safe ingestion with resume support
- Unchanged in Phase 3 (HooverEngine stable)

---

## Infrastructure

### [Error Handling - Security Scope](error-handling-security-scope.md)
**Topics:** Error handling for security-scoped bookmarks
- Bookmark stale detection
- User-friendly error messages
- Unchanged in Phase 3

---

## Phase 3 Architecture

**For AppStateOrchestrator:**
- **Architecture Doc:** `../architecture/COMPONENTS.md` - "Application State Coordination (Phase 3 Lazy Loading)" section
- **Code:** `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift`
- **Role:** Central coordinator replacing fragmented startup responsibilities

**For LightweightDiscoveryService:**
- **Implementation Guide:** [project-discovery-service-implementation.md](project-discovery-service-implementation.md) - "Tier 1: Lightweight Discovery" section
- **Code:** `app/Sources/ContextifyCore/Discovery/LightweightDiscoveryService.swift`
- **Role:** Stat-only scanning for <200ms startup

**For FastPathIngestionCoordinator:**
- **Architecture Doc:** `../architecture/COMPONENTS.md`
- **Code:** `app/Sources/ContextifyCore/Projects/FastPathIngestionCoordinator.swift`
- **Role:** JIT ingestion on project selection

---

## Relationship to Other Docs

- **Architecture/** - System-level context for how these components interact
- **Specifications/** - Data formats processed by these components
- **Guides/** - How to use, debug, or extend these components

---

## Updating These Docs

**When to update:**
- After significant refactoring of a component
- When adding new features to a component
- After performance optimizations or bug fixes that change behavior

**What to include:**
- Current implementation details
- API contracts and integration points
- Known limitations or edge cases

**What NOT to include:**
- Implementation plans (use /tmp/)
- Performance tuning TODOs (use TODOS.md)
- Historical "how it used to work" (unless critical context, then use archive/)
