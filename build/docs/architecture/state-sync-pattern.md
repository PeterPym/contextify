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

From `ProjectSwitcherState.switchToProject()`:

```swift
// Optimistic update - immediate UI feedback
@MainActor
func switchToProject(_ projectId: String) async {
  // IMMEDIATE UI UPDATE: Set activeProjectId now for instant visual feedback
  activeProjectId = projectId

  // Background write - coordinator will confirm/correct via handleContextUpdate()
  Task.detached(priority: .userInitiated) {
    await AppStateOrchestrator.shared.selectProject(id: projectId)
  }

  // Metadata update in separate background task
  Task.detached(priority: .userInitiated) {
    let result = try orchestrator.markProjectActivated(projectId: projectId, timestamp: ...)
    await MainActor.run { self?.unreadCounts[projectId] = result.unreadCount }
  }
}
```

From `ProjectSwitcherState.reorderProjects()`:

```swift
// Optimistic update with rollback on error
func reorderProjects(_ orderedProjectIds: [String]) async {
  // OPTIMIZATION: Update UI immediately
  updateTabProjects(reorderedTabs)
  allProjects = reorderedTabs + remainingProjects

  // Persist asynchronously, revert on failure
  Task {
    do {
      try orchestrator.setProjectDisplayOrderBulk(orderedProjectIds)
    } catch {
      await self.refreshProjects()  // Revert to DB state on error
    }
  }
}
```

### Database-Driven Pattern

From `ConversationMonitor.watchForDebouncedTranscriptUpdates()`:

```swift
// Background change - refresh from database via notification
private func watchForDebouncedTranscriptUpdates() async {
  for await note in NotificationCenter.default.notifications(named: "TranscriptUpdated") {
    if note.userInfo?["projectId"] == currentProjectId {
      debounceTask = Task {
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms debounce
        await processIncrementalUpdate()  // Fetches new entries from database
      }
    }
  }
}
```

## Architecture Rule

**UI -> ViewModel -> Orchestrator -> Repository -> Database**

Never skip layers. UI files must not import GRDB. Use `TranscriptOrchestrator` for all database operations.
