# State Sync Pattern - Hybrid Model

Contextify uses a **hybrid state synchronization pattern** that balances immediate UI feedback with database-backed consistency.

## Two Patterns for Different Scenarios

### 1. User-initiated, visible changes (optimistic updates)

- Apply optimistic UI update immediately (instant feedback)
- Write to database in background
- Reconciliation happens on next natural refresh point
- Example: Marking project as viewed, clearing unread counts

### 2. Background/invisible changes (database as source of truth)

- Database is canonical source
- UI refreshes on next relevant view load or notification
- Example: New transcript entries from file watcher, LLM summaries

## When is a Refresh Required?

A missing refresh is a **bug** only when:
- There's no optimistic update AND
- There's no natural reconciliation point AND
- The stale state is user-visible

## When is a Refresh Optional?

Refreshes can be deferred when:
- Optimistic update already applied (user sees immediate feedback)
- Natural reconciliation exists (next project switch, app restart)
- State is not immediately user-visible

## Examples

### Optimistic Update Pattern

```swift
// Optimistic update - immediate UI feedback
@MainActor
func markAsViewed() {
  unreadCounts[projectId] = 0  // Instant UI update

  // Background write - no explicit refresh needed
  Task.detached {
    try orchestrator.markProjectViewed(projectId: projectId, timestamp: Date())
    // Optimistic update already applied, no UI refresh required
  }
}
```

### Database-Driven Pattern

```swift
// Background change - refresh from database
func onNewTranscriptEntry(notification: Notification) async {
  // Refresh timeline from database
  await loadTimelineFromDatabase()

  // UI updates automatically via @Observable
}
```

## Architecture Rule

**UI -> ViewModel -> Orchestrator -> Repository -> Database**

Never skip layers. UI files must not import GRDB. Use `TranscriptOrchestrator` for all database operations.
