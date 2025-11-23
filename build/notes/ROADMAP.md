---
title: Product Roadmap & Research
type: exploratory
related: TODOS.md
description: Ideas, research questions, future possibilities. P4-P5 priority.
promotes_to: TODOS.md (once actionable)
priority_levels:
  P4: Future considerations - good ideas needing research/design before implementation
  P5: Research/exploratory - questions to investigate, no commitment to build
---

# Product Roadmap & Research

> **Exploratory ideas, research questions, and future possibilities.** Once scoped and actionable, items promote to [TODOS.md](TODOS.md).

---

## P4 (Future Considerations)

### P4-AUTONOMOUS-DEVELOPMENT: Self-Managing Development Pipeline

**Status:** Vision/concept
**Priority:** P4 (far future, research needed)
**Effort:** Very Large (multi-month initiative)

- [ ] Design and implement autonomous development agent for TODO management and execution

**Grand Vision:**
Owner only needs to review progress. Agent handles:
- TODO priority updates based on market signals
- Automatic task execution where safe/feasible
- Integration of external monitoring data

**Inputs:**
- Market research watchers (competitive analysis, feature trends)
- Transcript format watchers (upstream CLI changes)
- Customer support data (stubbed in `app/Sources/ContextifyCore/CustomerSupport/`)
- Build/test results
- Repository activity

**Agent Capabilities:**
1. **Priority Management**
   - Review TODOS.md regularly
   - Adjust priorities based on market signals, user feedback, technical dependencies
   - Flag stale items, suggest consolidation

2. **Autonomous Execution** (where safe)
   - Documentation updates
   - Test fixes
   - Dependency updates
   - Low-risk refactoring

3. **Human-in-Loop for Critical Work**
   - Submit PRs for review
   - Flag breaking changes
   - Request approval for architectural decisions

**Key Challenges:**
- Safety boundaries (what can agent change autonomously?)
- Quality assurance (how to validate agent work?)
- Cost management (LLM API usage)
- Error recovery (agent introduces bugs)

**Research Questions:**
1. What percentage of TODOs are "safe" for autonomous execution?
2. How to validate agent work without human review bottleneck?
3. What approval workflows enable speed without sacrificing safety?
4. How to integrate with existing git workflows (branch naming, PR templates)?

**Related Work:**
- TODOS.md#P2-TODOS-AGENT (intelligent TODO management - **promoted to P2**)
- TODOS.md#P3-AGENTIC-DEVOPS (transcript monitoring, conformance testing)
- Customer support stub (`CustomerSupport/` module)

### P4-WINDOW-KEEP-ON-TOP: Always-on-Top Window Option

**Status:** Not started
**Priority:** P4 (future consideration, UX design needed)
**Effort:** Small (UI toggle + window level management)

- [ ] Add user preference to keep Contextify window on top of other windows

**Motivation:**
- Users working with multiple tools (terminal, editor, browser) may want Contextify always visible
- Common pattern in utility/HUD apps (calculators, system monitors, clipboards)
- Helps maintain context during rapid tool switching

**Implementation Considerations:**
1. **UI**: Toggle in Settings or window titlebar/toolbar
2. **Window level**: Use `.floating` or `.statusBar` level (NSWindow.Level)
3. **Persistence**: Save preference per-project or globally?
4. **Interaction**: Should "on top" disable when app loses focus? Or stay truly always-on-top?
5. **Accessibility**: Ensure users can easily disable if it becomes annoying

**Research Questions:**
1. Should this be per-project or global preference?
2. What's the best macOS pattern for toggling window float state?
3. Should we auto-disable when user drags window? (prevent accidental "stuck" windows)

---

### P4-DISCOVERY-TOAST: Toast Notifications for Newly Discovered Projects

**Status:** Not started (demoted from P1)
**Priority:** P4 (nice-to-have UX polish)
**Effort:** Small (2-3 hours)
**Demoted From:** TODOS.md #32 (2025-11-22)

- [ ] Show toast notification when new projects are discovered

**Motivation:**
- User feedback: Nice-to-have but not blocking MVP
- Discovery already works silently in background
- Projects appear in tabs automatically

**Implementation:**
- Format: "New project discovered: [project-name]"
- Use existing toast system (NotificationCenter + `.contextifyShowToast`)
- Debounce rapid events (2-second window to batch multiple discoveries)

**Files:**
- `Contextify/Contextify/ContextifyApp.swift`
- `ProjectsViewModel.swift`

**Research Questions:**
1. Should toast show for ALL discovered projects or only NEW ones (never seen before)?
2. Should there be a user preference to disable discovery toasts?
3. Should toast link to the project (clicking switches to it)?

---

### P4-DIAGNOSTICS-HTTP-API: Restore Diagnostics HTTP Server

**Status:** Removed pre-launch, planned for restoration
**Priority:** P4 (post-launch feature for developer tooling)
**Effort:** Small (1-2 hours - restore previously removed code)

- [ ] Re-enable diagnostics HTTP server for external debugging and automation

**Background:**
HTTP server removed before initial App Store release (security/complexity concerns). Code preserved in git history for future restoration.

**Original Functionality:**
- Localhost-only HTTP server on port 17329
- External scripts could query timeline state, entries, diagnostics
- Helper script: `scripts/timeline_api.sh` (also removed)
- Endpoints: `/health`, `/diagnostics`, `/timeline/recent`, `/timeline/latest`

**Use Cases:**
- External debugging scripts querying app state
- Automated test harnesses validating timeline behavior
- Integration with developer tools (log analyzers, monitors)
- CI/CD health checks

**Restoration Plan:**
1. Revert removal commit or cherry-pick deleted files
2. Restore `DiagnosticsHTTPServer.swift` and `timeline_api.sh`
3. Make server opt-in via Settings pane or DEBUG-only flag
4. Update documentation with security notes (localhost-only binding)
5. Consider authentication/authorization for localhost endpoint

**Security Considerations:**
- Ensure server binds to 127.0.0.1 only (no network exposure)
- Consider auth token for localhost requests
- Document that HTTP server exposes internal state (intentional for debugging)

**Files to Restore (from git history):**
- `app/Sources/ContextifyCore/Diagnostics/DiagnosticsHTTPServer.swift`
- `scripts/timeline_api.sh`
- `ConversationMonitor.swift` initialization code

**Related:**
- P3-RESTORE-HTTP-API in TODOS.md (references this work)
- Original removal commit: `[will be documented in commit message]`

---

## P5 (Research / Exploratory)

### P5-INVESTIGATE-TRANSCRIPT-PROVIDERS: Other AI Tool Transcript Support

**Status:** Not started
**Priority:** P5 (exploratory, no current demand)
**Effort:** Low (initial survey), Variable (per-provider integration)

- [ ] Research transcript formats from other AI coding tools

**Candidates:** Cursor, Windsurf, Gemini CLI, Warp, Aider, Continue.dev

**Research Questions:**
1. Where stored? (local files, cloud, proprietary DB)
2. What format? (JSONL, SQLite, proprietary)
3. Documented/stable?
4. User demand?

**Potential Outcomes:**
- "Multi-provider" value prop for Contextify
- Broader market for the app
- Insights into transcript format best practices

---

**End of Roadmap**
