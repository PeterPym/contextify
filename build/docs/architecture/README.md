# Architecture Documentation

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

## Documents

### [Conversation Monitor State](conversation-monitor-state.md)
**Topics:** Timeline state management and real-time updates
- TimelineState observable model
- Entry filtering and session management
- System message handling

### ~~Data Flow~~ (ARCHIVED)
**Status:** Archived to `../archive/historical/data-flow-2025-10-22.md` (2025-11-17)
**Reason:** Not salvageable - architecture fundamentally changed since Oct 22
**Replacement:** See `../../notes/PROPOSED-DOCUMENTATION.md` #1 (Complete Data Pipeline Architecture)

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
- **Implementation:** Shipped (ProjectSwitcherState + ProjectSwitcherView)

### [Sandbox & App Store Architecture](sandbox-appstore-architecture.md)
**Topics:** Sandboxed vs unsandboxed builds, security-scoped bookmarks
- Security-scoped bookmark lifecycle and patterns
- DMG (unsandboxed) vs App Store (sandboxed) code paths
- Testing procedures and permission management
- Known sandbox-specific bugs and limitations
- **Critical for:** App Store builds, release testing, distribution

### [SQL Backend](sql-backend.md)
**Topics:** SQLite database architecture and schema design
- Tables, migrations (v1-v26), repositories
- GRDB integration
- Current schema: v26 (removed sandbox container path projects)

### [Startup Coordinator](startup-coordinator.md)
**Topics:** Deterministic project identity pipeline
- ActiveProjectContext design
- Startup sequencing
- AsyncStream-based updates
- **Implementation:** Shipped in commit 531ac70

### [Window System](window-system.md)
**Topics:** 4-window macOS app architecture
- Main HUD, Transcript Inventory, Projects, Settings
- Window management patterns
- **Note:** iTerm2 integration removed in commit 35ce380

---

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
