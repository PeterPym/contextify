# Architecture Documentation

**Last Updated:** 2025-11-18
**Context:** Updated to reflect lazy loading architecture refactor

**Start Here:** [COMPONENTS.md](COMPONENTS.md) - "Application State Coordination" section

---

System-level design documents describing how Contextify's major components fit together.

## Current Architecture Status

**Key architectural features:**
- ✅ Lazy loading architecture (10-35x faster startup)
- ✅ AppStateOrchestrator central coordinator
- ✅ Two-tier discovery (LightweightDiscoveryService + ProjectDiscoveryService)

**Architecture grade:** A-

## Purpose

This directory contains high-level architectural documentation that explains:
- Data flow through the system
- Major subsystem interactions
- Fundamental design decisions
- System-wide patterns and conventions

## Core Architecture

### [COMPONENTS.md](COMPONENTS.md)
**Topics:** Architecture overview and key components
- AppStateOrchestrator (central coordinator), LightweightDiscoveryService, lazy loading architecture
- **Start here** for understanding the system
- Performance summary: <200ms startup, 30-50 MB memory, 19 DB row updates

### [Data Pipeline Architecture](data-pipeline-architecture.md)
**Topics:** Complete data flow reference (5 levels of detail)
- Lightweight startup flow, JIT ingestion, background indexing
- Comprehensive with mermaid diagrams (1568 lines)
- Covers discovery → ingestion → database → timeline UI

### [Architecture Refactoring Analysis](architecture-refactoring-analysis.md)
**Topics:** Refactoring opportunities and roadmap
- Current state: 85% alignment achieved, architecture grade A- (up from B+)
- Phase 4 planning document
- Commits 080bb3c through 8a57385 analyzed

### [Startup Coordinator](startup-coordinator.md)
**Topics:** Startup sequencing and project identity
- StartupCoordinator is a legacy compatibility shim (AppStateOrchestrator is primary)
- Will be removed in Phase 4
- ActiveProjectContext design still relevant

---

## Specialized Topics

### [LLM Processing](llm-processing.md)
**Topics:** Dual-queue LLM architecture (FoundationLLM)
- TimelineCacheMissGenerator (queue #1: entry summaries)
- TranscriptMetadataOrchestrator (queue #2: document metadata)
- Status aggregation and monitoring

### [Project Switcher](project-switcher.md)
**Topics:** Multi-project tab navigation and state management
- Tab-based UI with drag-drop reordering
- Unread badge calculation and display
- Keyboard shortcuts and navigation
- Event-driven discovery and updates

### [SQL Backend](sql-backend.md)
**Topics:** SQLite database architecture and schema design
- Tables, migrations (v1-v26), repositories
- GRDB integration
- Current schema: v26

### [Sandbox & App Store Architecture](sandbox-appstore-architecture.md)
**Topics:** Sandboxed vs unsandboxed builds, security-scoped bookmarks
- Security-scoped bookmark lifecycle and patterns
- DMG (unsandboxed) vs App Store (sandboxed) code paths
- Testing procedures and permission management
- **Critical for:** App Store builds, release testing

### [Window System](window-system.md)
**Topics:** 4-window macOS app architecture
- Main HUD, Transcript Inventory, Projects, Settings
- Window management patterns
- **Note:** iTerm2 integration removed in commit 35ce380

---

## Legacy Documents

### [Conversation Monitor State](conversation-monitor-state.md)
**Topics:** Timeline state management and real-time updates
- TimelineState observable model
- Entry filtering and session management
- Planned refactor: ConversationMonitor will be split in Phase 4

### ~~Data Flow~~ (ARCHIVED)
**Status:** Archived to `../archive/historical/data-flow-2025-10-22.md` (2025-11-17)
**Reason:** Architecture fundamentally changed since Oct 22
**Replacement:** See [Data Pipeline Architecture](data-pipeline-architecture.md)

---

## Recommended Reading Order

### For Understanding Current Architecture

1. **[COMPONENTS.md](COMPONENTS.md)** - Start with "Application State Coordination" section
2. **[Data Pipeline Architecture](data-pipeline-architecture.md)** - Level 1-3 (Executive → Component → Flow Sequences)
3. **[Architecture Refactoring Analysis](architecture-refactoring-analysis.md)** - Current state and roadmap

### For Deep Dive

4. **[Data Pipeline Architecture](data-pipeline-architecture.md)** - Level 4-5 (Implementation Details → Technical Debt)
5. **[Startup Coordinator](startup-coordinator.md)** - Legacy integration patterns
6. **[LLM Processing](llm-processing.md)** - Timeline cache and dual LLM queues

### For Future Planning

7. **[Architecture Refactoring Analysis](architecture-refactoring-analysis.md)** - Full roadmap and deferred items
8. **[Conversation Monitor State](conversation-monitor-state.md)** - Planned refactoring work

---

## Related Implementation Guides

- [Project Discovery Service Implementation](../components/project-discovery-service-implementation.md) - Two-tier discovery (lightweight + full)
- [Startup Coordinator Implementation](../components/startup-coordinator-implementation.md) - Legacy integration patterns
- [Project Discovery](../components/project-discovery.md) - Lazy loading architecture overview

**Analysis Documents:**
- `../../notes/phase3-refactor-comparison-analysis.md` - Detailed architecture comparison (1458 lines)
- `../../notes/phase3-documentation-update-master-list.md` - Documentation tracking


## Relationship to Other Docs

- **Components/** - Detailed implementation of individual subsystems referenced here
- **Specifications/** - External data formats (Claude Code, Codex) consumed by the system
- **Guides/** - How to use the systems described here (diagnostics, debugging, etc.)

---

## Updating These Docs

**When to update:**
- After major architectural changes (new subsystem, data flow changes, etc.)
- After schema migrations (update SQL Backend doc)
- When removing or adding major components

**What NOT to include:**
- Implementation plans or TODO lists (use /tmp/ or TODOS.md)
- Gap analyses or feature proposals (use /tmp/)
- Historical "before/after" comparisons (use archive/ for historical context)
