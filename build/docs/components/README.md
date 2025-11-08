# Component Documentation

Component-specific implementation details for Contextify's individual subsystems.

## Purpose

This directory contains focused documentation on specific components:
- How they work internally
- APIs and integration points
- Configuration and usage patterns
- Performance characteristics

## Documents

### [Active Session Policy](active-session-policy.md)
**Component:** ActiveSessionPolicyEngine
**Topics:** Timeline follow behavior (automatic vs manual pin)
- Policy engine decision logic
- Follow mode persistence (schema v23)
- Switch reasons and notifications
- User-visible pin/unpin behavior

### [Database Migration](database-migration.md)
**Component:** DatabaseMigration
**Topics:** Custom database location and migration system
- Atomic migration with validation
- Security-scoped bookmarks for sandbox
- Multi-machine conflict detection
- Dropbox/iCloud sync support

### [Project Discovery](project-discovery.md)
**Component:** ConversationSources + ProjectDiscoveryService
**Topics:** Multi-project detection and monitoring
- Provider-specific scanners (Claude Code, Codex CLI)
- FSEvents-based file watching
- Worktree support

### [Timeline Cache](timeline-cache.md)
**Component:** TimelineCacheMissGenerator + TranscriptMetadataOrchestrator
**Topics:** LLM-generated summary caching
- Cache keys (content + window SHA256)
- Miss detection and batch generation
- Integration with FoundationLLM

### [Transcript Ingestion](transcript-ingestion.md)
**Component:** HooverEngine
**Topics:** Streaming JSONL parser for transcript files
- Batch processing and checkpointing
- Window tracking
- Crash-safe ingestion with resume support

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
