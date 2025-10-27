Project Switcher Navigation Bar Ð Architectural ReviewReview Date: 2025-10-27
Reviewer: Senior macOS Architect
Specification Version: Proposed
Related Features: Status Bar (implemented), Multi-project support1. EXECUTIVE SUMMARYWhat the Feature Does:

Multi-project dashboard: Transforms Contextify from single-project monitoring to simultaneous multi-project monitoring with a horizontal navigation bar
Global discovery: Scans all Claude Code project directories (~/.claude/projects/, ~/.codex/sessions/) every 30 seconds to discover projects with active transcripts
Persistent watching: Maintains filesystem watchers for all discovered projects simultaneously (no teardown on switch)
Unread tracking: Database-backed visit timestamps with calculated unread counts per project, incrementing on non-active project updates
Quick switching: Click-to-switch navigation with automatic timeline refresh and git info updates
Visual feedback: Unread badges (e.g., "api-server (3)") with active state highlighting
Event-driven UI: AsyncStream-based state updates following established StatusBar patterns
Top Risks:

?? CRITICAL: Race conditions in multi-project watcher lifecycle Ð Re-discovery may double-start watchers; no explicit deduplication strategy in ProjectActivityMonitor spec (HIGH likelihood, HIGH impact)
?? CRITICAL: Unread count integrity under clock skew Ð Relying on wall-clock timestamps for unread calculation; system clock changes or multi-device scenarios break correctness (MEDIUM likelihood, HIGH impact)
?? HIGH: Performance degradation with N projects Ð Linear scaling of filesystem watchers (N ? transcripts ? watchers) with no backpressure mechanism; 30s polling overhead grows unbounded (HIGH likelihood, MEDIUM impact)
?? HIGH: Missing transaction boundaries Ð Unread increment and visit updates lack explicit transaction wrapping; concurrent switches may lose updates (MEDIUM likelihood, MEDIUM impact)
?? HIGH: 30-second discovery latency Ð New projects invisible for up to 30s; polling-based discovery when event-driven (FSEvents on ~/.claude/) is feasible (HIGH likelihood, LOW impact - UX)
?? MEDIUM: Undefined reverse path mangling Ð No specification for reversing Claude Code's path mangling; "reverse Claude Code's path mangling" is underspecified (HIGH likelihood, MEDIUM impact)
?? MEDIUM: First-visit ambiguity Ð "Never visited project" spec says "show all entries as unread" but doesn't specify NULL vs MIN(timestamp) vs explicit sentinel (MEDIUM likelihood, MEDIUM impact)
?? MEDIUM: Actor isolation gaps Ð ProjectActivityMonitor has no actor annotation; unclear if it's meant to be actor, @MainActor, or unstructured concurrent access (MEDIUM likelihood, MEDIUM impact)
?? LOW: StatusBar integration untested Ð Both components render in same window; no explicit z-index or layout conflict testing mentioned (LOW likelihood, LOW impact)
?? LOW: Missing cancellation on rapid switching Ð Spec mentions "cancel in-flight timeline loads" but no API surface defined on HUDViewModel or ConversationMonitor (LOW likelihood, MEDIUM impact)
Readiness Assessment: ?? NOT READY TO START Ð Critical architectural decisions missing (watcher lifecycle, actor boundaries, transaction strategy). Recommend 2-3 day design sprint to define actor model, deduplication strategy, and transaction boundaries before Phase 1.2. SYSTEM DIAGRAMCurrent Architecture (Single Project)