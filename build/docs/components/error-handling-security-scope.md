# Security Scope Error Handling

**Component:** TranscriptAccessProvider, TranscriptOrchestrator
**Error Type:** `FolderAccessError.securityScopeAccessDenied`

---

## Policy

Error handling differs based on call context:

### UI-Initiated Actions (Show Error to User)

**Examples:**
- User clicks "Discover Projects" button
- User manually triggers ingestion
- User opens settings and tests permissions

**Behavior:**
- Let `FolderAccessError` bubble to UI layer
- `ProjectsViewModel` catches and sets `errorMessage` property
- User sees: "Discovery failed: Contextify doesn't have permission to..."

**Code:**
```swift
// In ProjectsViewModel.discoverProjects()
do {
  let discovered = try await discoveryService.discoverAllProjects(...)
  projects = discovered
} catch {
  logger.error("Discovery failed: \(error.localizedDescription)")
  errorMessage = "Discovery failed: \(error.localizedDescription)"
}
```

### Background Actions (Log and Continue)

**Examples:**
- FSEvents detects file change (DMG builds only)
- Periodic refresh (future feature)
- Maintenance tasks

**Behavior:**
- Catch `FolderAccessError` and log warning
- Continue processing other items
- Don't show modal/alert to user (avoid spam)

**Code:**
```swift
// In FSEvents handler (if re-enabled for sandbox)
Task {
  do {
    try await orchestrator.discoverTranscript(...)
  } catch let error as FolderAccessError {
    log.warning("FSEvents: skipping transcript - permission not granted: \(error)")
  } catch {
    log.error("FSEvents: hoover failed: \(error)")
  }
}
```

---

## User-Facing Error Messages (Future Enhancement)

Currently: Uses default `error.localizedDescription`

**Better:**
```swift
private func userFacingMessage(for error: Error) -> String {
  if let e = error as? FolderAccessError {
    switch e {
    case .securityScopeAccessDenied(let url):
      let path = url?.path ?? "transcript directory"
      return """
      Contextify doesn't have permission to access \(path).

      Please re-authorize in Settings or restart onboarding.
      """
    default:
      break
    }
  }
  return "Discovery failed: \(error.localizedDescription)"
}
```

**Location:** `Contextify/Contextify/ProjectsViewModel.swift`

---

## Permission Recovery Flow (Future Enhancement)

**Current:** User must restart app and go through onboarding again

**Better:**
1. Show error with "Grant Permission" button
2. Button opens settings or re-triggers folder picker
3. User selects folder
4. Retry discovery automatically

**Components needed:**
- Settings UI for permission management
- Re-authorization flow without full onboarding
- Reactive update when permissions change

---

## Implementation Status

**Currently implemented:**
- ✅ Error propagation from Core to App layer
- ✅ Logging at debug/error levels
- ✅ Basic error messages in UI (via `localizedDescription`)

**Future work:**
- ⏳ Improved user-facing error messages
- ⏳ In-app permission recovery flow
- ⏳ Settings UI for permission management
