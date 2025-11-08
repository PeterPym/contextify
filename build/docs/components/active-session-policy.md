# Active Session Policy - Timeline Follow Behavior

**Status:** Shipped (schema v23)
**Components:** ActiveSessionPolicyEngine.swift, ActiveSessionEvents.swift
**Related:** ConversationMonitor, TranscriptInventory, project_follow_policy table

Controls whether the timeline automatically follows the newest active transcript or stays pinned to a user-selected session.

---

## Overview

**Problem:** When monitoring multiple Claude Code/Codex sessions simultaneously, which session should the timeline display?

**Solutions:**
1. **Automatic Mode** - Follow the newest transcript with recent activity
2. **Manual Mode** - Stay pinned to user-selected session (ignore new writes)

**User Control:**
- Click session in Transcript Inventory → pins to that session
- Click "Unpin" → returns to automatic mode
- Automatic by default

---

## Architecture

### Core Components

**ActiveSessionPolicyEngine** (pure function)
- Input: current state (follow mode, last active, newest candidate, cooldown)
- Output: `Decision` (next session to activate, should emit notification, reason)
- No side effects - testable pure logic

**ConversationMonitor** (stateful orchestrator)
- Owns `followMode: FollowMode` (`@Observable`)
- Calls policy engine on transcript changes
- Applies decisions (set active session, emit events)
- Persists mode to database (`project_follow_policy` table)

**ActiveSessionEvents** (notification bridge)
- Typed event structure for session switches
- Published via `NotificationCenter.default.post`
- UI components observe to update indicators

---

## Follow Modes

### Automatic Mode

**Behavior:**
```swift
case .automatic
```

**Logic:**
- On transcript write: check if it's newer than current active session
- If yes → switch to that session (subject to cooldown)
- If no → stay on current session

**Use Case:** Developer wants to see their most recent work across all projects

**Example:**
```
10:00 - Working in Project A, session A-123
10:05 - Write to Project B, session B-456 → timeline switches to B-456
10:10 - Continue in Project B → timeline stays on B-456
```

### Manual Mode (Pinned)

**Behavior:**
```swift
case .manual(sessionId: String, provider: Provider)
```

**Logic:**
- Ignore all new transcript writes
- Stay locked on pinned session until user unpins
- If pinned session deleted → automatic fallback with `.pinnedMissing` reason

**Use Case:** Developer reviewing specific past session while other sessions are active

**Example:**
```
10:00 - User clicks session A-123 in Transcript Inventory
       → Timeline pins to A-123
10:05 - New write to session B-456 (active work)
       → Timeline STAYS on A-123 (pinned)
10:10 - User clicks "Unpin" → Timeline switches to B-456
```

---

## Policy Engine Logic

### Decision Algorithm

```swift
func decide(inputs: Inputs) -> Decision {
  // 1. Determine target based on mode
  let target: SessionKey? = {
    switch followMode {
    case .automatic:
      return newestCandidate  // Most recent write
    case .manual(sid, prov):
      return SessionKey(sid, prov)  // Pinned session
    }
  }()

  // 2. No target available
  guard let target else {
    return Decision(nextActive: nil, shouldEmitMessage: false, reason: nil)
  }

  // 3. Already at target
  guard lastActiveKey != target else {
    return Decision(nextActive: nil, shouldEmitMessage: false, reason: nil)
  }

  // 4. Check global cooldown
  if let lastSwitch = lastSwitchAt,
     now.timeIntervalSince(lastSwitch) < cooldown {
    // Still switch, but suppress notification
    return Decision(nextActive: target, shouldEmitMessage: false, reason: .newerWrite)
  }

  // 5. Switch and emit
  return Decision(nextActive: target, shouldEmitMessage: true, reason: .newerWrite)
}
```

### Global Cooldown

**Purpose:** Prevent notification spam during rapid transcript writes

**Implementation:**
- 5-second cooldown window
- Suppress message emission (but still switch session)
- User doesn't see toast notifications for every switch

**Example:**
```
10:00:00 - Write to session A → switch + notification
10:00:02 - Write to session B → switch, NO notification (within 5s)
10:00:04 - Write to session C → switch, NO notification (within 5s)
10:00:06 - Write to session D → switch + notification (cooldown expired)
```

---

## Database Persistence (Schema v23)

### Table: `project_follow_policy`

```sql
CREATE TABLE project_follow_policy (
  project_id TEXT PRIMARY KEY,
  mode INTEGER NOT NULL DEFAULT 0,  -- 0=auto, 1=manual
  pinned_session_id TEXT,
  pinned_provider TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
);
```

### Persistence Logic

**On Mode Change:**
```swift
// User pins to session
try orchestrator.setFollowPolicy(
  projectId: currentProjectId,
  mode: .manual(sessionId: "ABC-123", provider: .claudeCode)
)

// User unpins
try orchestrator.setFollowPolicy(
  projectId: currentProjectId,
  mode: .automatic
)
```

**On Project Switch:**
```swift
// Load persisted policy for new project
let policy = try orchestrator.getFollowPolicy(projectId: newProjectId)
followMode = policy?.mode ?? .automatic  // Default to auto if not set
```

**Result:** Pin state preserved per-project across app restarts

---

## Switch Reasons

```swift
enum SwitchReason: String {
  case newerWrite       // Automatic: new transcript activity
  case manualSelection  // User clicked session in inventory
  case unpinToAuto      // User clicked "Unpin" button
  case projectChange    // User switched projects
  case pinnedMissing    // Pinned session no longer exists
}
```

**User-Visible Messages:**

| Reason | Display Text |
|--------|-------------|
| `newerWrite` | "Switched to [session] (newer activity)" |
| `manualSelection` | "Pinned to [session]" |
| `unpinToAuto` | "Unpinned - following newest activity" |
| `projectChange` | (No message - implicit) |
| `pinnedMissing` | "Pinned session unavailable - following newest" |

---

## Event Notifications

### ActiveSessionDidChangeEvent

**Structure:**
```swift
struct ActiveSessionDidChangeEvent: Sendable {
  let projectId: String
  let projectPath: String
  let sessionId: String
  let provider: String
  let mode: String       // "automatic" | "manual"
  let reason: String     // SwitchReason.rawValue
  let timestamp: Date
}
```

**Publishing:**
```swift
let event = ActiveSessionDidChangeEvent(
  projectId: currentProjectId,
  projectPath: currentProjectPath,
  sessionId: newSession.id,
  provider: newSession.provider.rawValue,
  mode: followMode.isAutomatic ? "automatic" : "manual",
  reason: reason.rawValue,
  timestamp: Date()
)

NotificationCenter.default.post(
  name: .activeSessionDidChange,
  object: event
)
```

**Observers (UI):**
```swift
NotificationCenter.default.addObserver(
  forName: .activeSessionDidChange,
  object: nil,
  queue: .main
) { notification in
  guard let event = notification.activeSessionEvent else { return }
  print("Switched to \(event.sessionId) - \(event.reason)")
  // Update UI: pin indicator, session badge, etc.
}
```

---

## UI Integration

### Transcript Inventory Window

**Pin Indicator:**
- Pinned session: Blue pin icon next to session name
- Other sessions: No icon (grayed out)

**Unpin Button:**
- Visible only when in manual mode
- Click → `unpinToAuto()` → automatic mode + notification

**User Workflow:**
1. Open Transcript Inventory (`Cmd+Ctrl+I`)
2. Click any session row → timeline switches + pins
3. Close window → timeline stays pinned
4. New writes in other sessions → ignored
5. Reopen window, click "Unpin" → back to automatic

### Main Timeline Header

**Mode Indicator (Proposed):**
```
🔒 Pinned to session ABC-123
```
or
```
🔄 Following newest activity
```

*(Currently not implemented - policy is "silent" except for notifications)*

---

## Reconciliation & Edge Cases

### Pinned Session Deleted

**Scenario:** User pins to session, then deletes transcript file

**Detection:**
```swift
// On transcript scan
if followMode.isManual(sessionId: sid, provider: prov) {
  if !transcriptExists(sid, prov) {
    followMode = .automatic
    reason = .pinnedMissing
    // Switch to newest available session
  }
}
```

**Result:** Automatic fallback + notification "Pinned session unavailable"

### Project Switch

**Scenario:** User switches from Project A (pinned) to Project B

**Behavior:**
1. Load Project B's persisted policy from DB
2. If B was auto → automatic mode
3. If B was pinned → restore pinned session (if still exists)

**Per-Project State:** Each project remembers its own pin state

### No Sessions Available

**Scenario:** All transcripts deleted, no sessions left

**Behavior:**
```swift
if allSessions.isEmpty {
  activeSession = nil
  followMode = .automatic  // Reset to automatic
  // Timeline shows "No transcripts found"
}
```

---

## Performance Characteristics

| Operation | Timing | Notes |
|-----------|--------|-------|
| Policy decision | <1ms | Pure function, no I/O |
| Mode persistence | ~10ms | Single INSERT/UPDATE |
| Mode restoration | ~5ms | Single SELECT query |
| Cooldown check | <1ms | Date comparison |

**Optimization:**
- Policy engine is pure (no DB lookup in decision path)
- Persistence is async (doesn't block UI)
- Cooldown prevents excessive DB writes during rapid switches

---

## Testing

### Unit Tests (PolicyEngine)

```swift
func testAutomaticMode() {
  let engine = ActiveSessionPolicyEngine()
  let decision = engine.decide(inputs: .init(
    followMode: .automatic,
    lastActiveKey: SessionKey(sessionId: "A", provider: .claudeCode),
    newestCandidate: SessionKey(sessionId: "B", provider: .claudeCode),
    now: Date(),
    lastSwitchAt: nil,
    cooldown: 5.0
  ))

  XCTAssertEqual(decision.nextActive?.sessionId, "B")
  XCTAssertTrue(decision.shouldEmitMessage)
  XCTAssertEqual(decision.reason, .newerWrite)
}

func testCooldownSuppressesMessage() {
  let engine = ActiveSessionPolicyEngine()
  let now = Date()
  let decision = engine.decide(inputs: .init(
    followMode: .automatic,
    lastActiveKey: SessionKey(sessionId: "A", provider: .claudeCode),
    newestCandidate: SessionKey(sessionId: "B", provider: .claudeCode),
    now: now,
    lastSwitchAt: now.addingTimeInterval(-2),  // 2s ago (within 5s cooldown)
    cooldown: 5.0
  ))

  XCTAssertEqual(decision.nextActive?.sessionId, "B")  // Still switches
  XCTAssertFalse(decision.shouldEmitMessage)  // But no notification
}
```

### Manual Testing

**Pin/Unpin:**
1. Open Transcript Inventory
2. Click any session → verify timeline switches + pin icon appears
3. Start new Claude Code session → verify timeline doesn't switch
4. Click "Unpin" → verify timeline switches to newest session

**Persistence:**
1. Pin to session A in Project 1
2. Quit app
3. Relaunch → verify Project 1 still pinned to session A

**Missing Session:**
1. Pin to session A
2. Delete transcript file
3. Verify automatic fallback + notification

---

## Known Limitations

1. **No UI indicator:** Main timeline doesn't show pin status (only via Transcript Inventory)
2. **No history:** Can't see past switches or reasons after notification dismisses
3. **Per-project only:** Can't have global pin across all projects
4. **No temporary pin:** Pin persists until explicitly unpinned (no "pin for 10 minutes" mode)

---

## Future Enhancements

**Out of Scope (Current Release):**
- Timeline header showing pin status
- Pin history log
- Temporary pin with timeout
- Pin multiple sessions (split-screen)
- Auto-unpin after N minutes of inactivity

**Potential Improvements:**
- Configurable cooldown duration (currently hardcoded 5s)
- Per-session auto-unpin rules ("unpin when this session closes")
- Visual timeline annotation showing switch points

---

## Related Documentation

- `build/docs/architecture/conversation-monitor-state.md` - Timeline state management
- `build/docs/components/transcript-ingestion.md` - How transcript writes trigger policy checks
- `build/docs/architecture/sql-backend.md` - Database schema (v23)

---

## Debugging

### Enable Policy Logs

**Console Filter:**
```
subsystem:dev.contextify category:ConversationMonitor
```

**Key Log Messages:**
```
Policy decision: switch to [session] (reason: newerWrite)
Switched to automatic mode due to pinned session missing
Pinned to session [id] (manual selection)
Cooldown active: switch without notification
```

### Diagnostics API

**Check Current Mode:**
```bash
curl http://localhost:17329/diagnostics | jq '.followMode'
```

**Output:**
```json
{
  "mode": "manual",
  "pinnedSessionId": "ABC-123",
  "pinnedProvider": "claude.code"
}
```
