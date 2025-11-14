# Logging Preferences & Guidelines

**For:** Contextify macOS HUD
**Framework:** OSLog (`import OSLog`)
**Logger Setup:** `Logger(subsystem: "dev.contextify", category: "CategoryName")`

## Overview

This document provides detailed logging guidelines for Contextify development. Follow Apple's Unified Logging semantics with a two-phase approach that balances development velocity with production log cleanliness.

### Pipeline telemetry tags

Several tags are now considered "infrastructure logs" and **must remain at `.info`** so diagnostics
scripts can detect them. Do not demote or remove these unless you provide an equivalent signal.

| Tag prefix | Emitted by | Purpose |
|------------|------------|---------|
| `[FSEVENTS-WATCH-*]`, `[FSEVENTS-CHANGE]`, `[FSEVENTS-HEARTBEAT]` | `TranscriptWatcher` | Confirms file-system watchers are alive and reacting to changes |
| `[DB-UPDATE]` | `HooverEngine` | Indicates rows were persisted; used by pipeline analyzer |
| `[PREFLIGHT-CACHE-*]` | `TranscriptOrchestrator` | Shows cache hits/misses for corrupt transcript triage |
| `[TIMELINE-HYDRATE-*]` | `ConversationMonitor` | Measures timeline load latency for gap analysis |
| `[HOOVER-SCHED-*]` | `HooverScheduler` | Reports queue depth + duplicate suppression |

Scripts such as `monitor-pipeline-check.sh`, `monitor-transcript-queues.sh`, `analyze-pipeline.sh`,
and `analyze-gaps.sh` depend on these tags to report stage-by-stage health. When adding new
subsystems, emit analogous tags so telemetry stays complete.

## Two-Phase Logging Strategy

### Phase 1: Initial Development (feature branch)
- Use `.info` generously during feature buildout to track execution flow
- Add `.debug` for verbose implementation details
- Use `.warning` for unexpected-but-handled conditions
- Use `.error` for actual errors requiring attention

### Phase 2: Pre-merge Cleanup (before PR/commit)
- **Move routine operations to `.debug`** - anything that happens during normal, successful execution
- **Keep `.info` for significant state changes** - session switches, monitoring started/stopped, file watching
- **Keep `.warning` for retries, fallbacks, unusual conditions** - LLM retries, cache regenerations, timeout warnings
- **Keep `.error` for failures** - parse errors, missing files, LLM unavailable

## Log Level Reference

| Level | When to Use | Examples | User Visibility |
|-------|-------------|----------|-----------------|
| `.debug` | Normal operation details, success paths, routine events | "Cache HIT", "Loaded 10 entries", "LLM SUCCESS", "SystemLanguageModel available" | Hidden with `TYPE Info` filter |
| `.info` | Significant state changes, important milestones | "Watching transcript: [file]", "Switched to Codex conversation", "Created new cache" | Visible in production |
| `.notice` | Not used in this project | N/A | N/A |
| `.warning` | Recoverable issues, retries, degraded operation | "LLM retry 2/3", "Cache REGENERATE (content changed)", "Accessibility permissions not granted" | Visible, needs attention |
| `.error` | Failures requiring intervention | "Failed to parse JSON", "LLM unavailable", "No conversation file found" | Visible, actionable |
| `.fault` | Critical bugs, should-never-happen conditions | Use `assertionFailure()` instead | Crashes in debug builds |

## Practical Examples

### During Development

It's OK to use `.info` liberally while developing:

```swift
log.info("🟢 processConversationFile: read \(lines.count) lines")  // OK during development
log.info("Cache HIT for \(uuid)")  // OK during development
log.info("LLM SUCCESS - disposition=\(payload.disposition)")  // OK during development
```

### Before Merge

Move routine operations to `.debug`:

```swift
log.debug("🟢 processConversationFile: read \(lines.count) lines")  // Normal operation
log.debug("Cache HIT for \(uuid)")  // Normal operation
log.debug("LLM SUCCESS - disposition=\(payload.disposition)")  // Success path
```

### Production Logs

Keep only significant events at `.info` or higher:

```swift
log.info("Watching transcript: \(fileURL.lastPathComponent)")  // State change
log.warning("LLM retry \(retryCount)/\(maxRetries)")  // Retry attempt
log.error("Failed to load timeline cache: \(error)")  // Error condition
```

## Special Cases

### Retry Logic

Distinguish between normal first attempts and problem retries:

```swift
if retryCount == 0 {
  log.debug("Requesting LLM summary (retry 0/3)")  // Normal first attempt
} else {
  log.warning("Requesting LLM summary (retry \(retryCount)/3)")  // Something's wrong
}
```

**Rule:** First attempt `.debug` (normal), retries 1+ use `.warning` (degraded)

### Startup & Initialization

- Keep key initialization steps at `.info` (helps debug startup issues)
- Move routine sub-steps to `.debug`
- Example:
  ```swift
  log.info("Initializing ConversationMonitor")  // Key milestone
  log.debug("Loading timeline cache from disk")  // Routine sub-step
  log.debug("Registering file watchers")  // Routine sub-step
  ```

### Emojis in Logs

- **Development:** Use sparingly, only for visual scanning
- **Pre-merge:** Remove or simplify decorative emojis
  - "🟢" → none
  - "✅" → none
  - "📝" → none
- **Keep error indicators:** "🔴" or "⚠️" acceptable for warnings/errors

## Console Filtering

Users should configure the Xcode console with `TYPE Info` filter to hide debug logs. This creates:
- **Clean production logs** - only state changes, warnings, and errors
- **Detailed debug info** - available when needed for troubleshooting

See README.md for console setup instructions.

## Anti-Patterns

**❌ Don't do this:**
```swift
// Logging normal success at .info (pre-merge)
log.info("Parsed message successfully")

// Logging routine operations at .info (pre-merge)
log.info("Cache hit for entry \(id)")

// Logging errors at .debug
log.debug("Failed to parse: \(error)")  // Should be .error
```

**✅ Do this instead:**
```swift
// Normal success at .debug
log.debug("Parsed message successfully")

// Routine operations at .debug
log.debug("Cache hit for entry \(id)")

// Errors at .error
log.error("Failed to parse: \(error)")
```

## Summary Checklist

Before merging code, verify:
- [ ] Routine operations (normal flow, cache hits, successful parsing) → `.debug`
- [ ] Significant state changes (watching files, session switches) → `.info`
- [ ] Retries and fallbacks → `.warning`
- [ ] Failures and errors → `.error`
- [ ] Decorative emojis removed (keep error indicators only)
- [ ] Console output clean when filtered to `TYPE Info`

---

**See also:**
- `CLAUDE.md` for quick reference version of these guidelines
- `feature-flags.md` for developer mode and debug tool visibility
