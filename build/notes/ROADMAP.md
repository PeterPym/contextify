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

### CHECKMARK-SCROLL: Completion checkmark should scroll to linked directive

**Status:** Research needed
**Priority:** P4
**Effort:** 1-2 hours

- [ ] Make green checkmark scroll to original directive instead of expanding row

**Idea:** When a completion entry (green checkmark) is linked to a user directive, clicking the checkmark should scroll to that directive. Currently row's `.onTapGesture` captures all clicks.

**Challenge:** SwiftUI gesture handling - tried `Button`, `.highPriorityGesture`, `.simultaneousGesture` but row's tap gesture still captures. Need to research gesture exclusion or view restructuring.

**Location:** `TimelineEntryRow.swift` - checkmark and scroll-to logic around lines 297-319 (line numbers drift; search for `isCompletion`)

---

### HOMEBREW-CASK: Homebrew Cask formula for DMG distribution

**Status:** Not started
**Priority:** P4
**Effort:** 1-2 hours

- [ ] Create Homebrew Cask formula for Contextify DMG

**Scope:** Create a Homebrew Cask formula so users can install via `brew install --cask contextify`. Requires:
- Formula file with download URL, SHA256, app name
- Submit to homebrew-cask or host in custom tap

---

### RELEASE-STATUS-BAR: Claude Code status line for release version

**Status:** Not started
**Priority:** P4
**Effort:** 2-4 hours

- [ ] Add Claude Code status line showing current release version

**Idea:** Configure Claude Code's status line to display current release version being worked on. Would show something like `v1.0.0 build:4 phase:review_materials`. Nice-to-have developer convenience.

---

### THIRD-PARTY-LLM: Alternative LLM providers for Lite Mode users

**Status:** Research needed
**Priority:** P4
**Effort:** 8-12 hours

- [ ] Investigate Ollama/OpenAI/Anthropic integration for macOS 15 users

**Context:** Lite Mode (shipped) gives macOS 15 users timeline/search without summaries. Some users may want AI summaries via third-party LLMs instead of waiting for macOS 26.

**Options to research:**
1. **Ollama** - Local models, no API key needed
2. **OpenAI/Anthropic API** - User provides own key
3. **Both** - User chooses in Settings

**Considerations:**
- Cost model (API calls vs local)
- Privacy implications (sending transcripts to cloud)
- UI for API key management
- Quality parity with Apple Intelligence

**Note:** This replaces the original OS-COMPATIBILITY entry. The compatibility modal approach was superseded by Lite Mode implementation.

---

### CM-REFACTOR: ConversationMonitor Further Refactoring

**Status:** Phases 1-3 complete, further work paused (diminishing returns)
**Priority:** P4 (future consideration)
**Completed phases:** 2025-12-26

ConversationMonitor refactoring to reduce "god object" complexity. Phases 1-3 extracted 4 coordinators totaling 1,572 lines. CM reduced from ~3,500 to 2,880 lines.

**Completed:**
- [x] Phase 1A: HealthMonitoringCoordinator (268 lines) - health checks, auto-recovery, backoff
- [x] Phase 1B: ViewportTrackingCoordinator (521 lines) - viewport state machine, visibility, scroll
- [x] Phase 2: TimelineDataLoader (468 lines) - background DB queries, cursor, decoration data
- [x] Phase 3: TimelineCacheCoordinator (315 lines) - cache miss creation, queue management

**Key improvements achieved:**
- DB work moved off main thread (background actor)
- Single authoritative cursor and seenEntryIDs (no split-brain)
- Defensive guards: feedLoadGeneration token, project mismatch errors
- Cancellation safety throughout async paths
- External code review with hardening fixes

**Future candidates (if needed):**
- NotificationHub/ObserverCoordinator - consolidate 7+ observer lifecycle management
- ActiveSessionFollowCoordinator - isolate policy decisions from ingestion
- TimelineEntryMapper - centralize entry transformation

**Decision rule for future phases:**
Continue only if extraction reduces correctness risk, performance risk, or change velocity.
Pause if no crisp contract or only chasing line reduction.

**Analysis:** `/tmp/colleague-response-analysis.md`, `/tmp/conversation-monitor-refactoring-assessment.md`

---

### GIT-ACTIVITY: Git activity tracking and work story visualization

**Status:** Not started
**Priority:** P4
**Effort:** 13-18 hours

- [ ] Parse transcripts for git commands and show work narrative

**Vision:** Transform transcripts into work story. Show ahead/behind main, staged/unstaged counts, commit badges, timeline visualization of work progression.

**Related:** See `/tmp/PROJECT-CHRONICLE-spec.md` for broader "development narrative" thinking that could subsume this. Git data (branches, commits, merges gleaned from conversations) would be one input source feeding the narrative synthesis.

---

### RESUME-FORK: Resume and fork conversations from search

**Status:** Spec complete
**Priority:** P4
**Effort:** 2-3 weeks

- [ ] Resume/fork conversations from search results

**Vision:** Right-click transcripts to "Resume this conversation" or "Fork from here". Contextify becomes workflow participant, not just observer.

**Spec:** `build/notes/todo-support/RESUME-FORK-spec.md`

---

### RELEASE-NOTES-JSON: JSON-based release notes generation

**Status:** Spec complete
**Priority:** P4
**Effort:** 4-6 hours

- [ ] Single-source JSON release notes with multi-output generation

**Problem:** Release notes maintained manually in multiple places. JSON source would generate Sparkle HTML, CHANGELOG.md, App Store text.

---

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

### P4-MENUBAR-ICON: NSStatusBar Menubar Icon with Processing Status

**Status:** Not started (demoted from P1)
**Priority:** P4 (nice-to-have - always-on access)
**Effort:** Medium (6-8 hours)
**Demoted From:** TODOS.md #54+#55 (2025-11-22)

- [ ] Implement NSStatusBar menubar icon showing processing status and errors

**Motivation:**
- Always-on access to Contextify when window is closed
- Quick glance at processing status (hoovering, LLM queue, errors)
- Common pattern in utility/background apps (Dropbox, Time Machine, etc.)

**Features:**
- Menubar icon that shows app status
- Processing indicator (animated when hoovering/processing)
- Error badge when issues occur
- Click to show/hide main window
- Right-click for quick actions menu

**Implementation:**
- `NSStatusBar` API for menubar integration
- Status item with dynamic icon (idle/processing/error states)
- Menu with quick actions: Show Window, Check for Updates, Quit
- Show error count badge when transcripts fail parsing or LLM errors

**Files:**
- `Contextify/Contextify/AppDelegate.swift` (existing TODO comment line 83)
- New: `Contextify/Contextify/StatusBarController.swift`

**Research Questions:**
1. Should menubar icon be optional (user preference to show/hide)?
2. What icon states are most useful? (idle, processing, error, paused)
3. Should clicking icon toggle window or show menu?

---

### P4-CORRUPT-TRANSCRIPT-WARNING: Surface Corrupt Transcripts in UI

**Status:** Not started (demoted from P1)
**Priority:** P4 (nice-to-have - diagnostic visibility)
**Effort:** Small (1-2 hours)
**Demoted From:** TODOS.md #56 (2025-11-22)

- [ ] Show warning indicators for transcripts with parsing errors

**Motivation:**
- Help users identify problematic transcripts at a glance
- Related to transcript repair (#58-59 in P2) but separate concern
- #58-59 = repair actions, #56 = visual warnings

**Implementation:**
- Show orange warning icon (⚠️) in session rows for corrupt transcripts
- Tooltip on hover: "Transcript has parsing errors - [error type]"
- Click to show error details or repair options
- Badge count in project tab if project has corrupt transcripts

**Files:**
- `Contextify/Contextify/TranscriptInventoryView.swift`
- `Contextify/Contextify/TimelineEntryRow.swift` (for error badges)

**Note:** May already be covered by #58-59 implementation (P2 transcript repair MVP). Validate if separate work is needed.

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

### P4-AWAY-SUMMARY: Summarize Activity While User Was Away

**Status:** Not started
**Priority:** P4 (future consideration, UX innovation)
**Effort:** Medium-Large (6-10 hours)

- [ ] Detect user idle/away state and summarize conversation activity on return

**Motivation:**
When users step away from their machine (lunch, meetings, overnight), Claude Code sessions may continue running long tasks. Upon return, users currently must scroll through potentially dozens of entries to understand what happened.

**Core Features:**
1. **Idle Detection:** Monitor system idle time (mouse/keyboard inactivity)
2. **Away Threshold:** Configurable threshold (e.g., 15 minutes) to trigger "away" state
3. **Return Summary:** When user returns and > N entries added during absence, show concise summary
4. **Action Items:** Surface any action items, errors, or decisions requiring attention

**UX Concepts:**
- **Banner/Toast:** "While you were away: 47 new entries across 3 projects"
- **Summary Panel:** Expandable panel with key highlights
- **Action Queue:** List items needing user attention (errors, prompts, completions)

**Implementation Considerations:**
1. **Idle Detection:** Use `NSEvent.addGlobalMonitorForEvents` or `IOKit` for HID idle time
2. **Entry Threshold:** Only summarize if > N entries (e.g., 10) added during absence
3. **Summary Generation:** Use existing LLM infrastructure or simple heuristics
4. **Per-Project vs Global:** Summary could be project-specific or aggregate
5. **Dismissal:** User can dismiss or "mark as read" to clear away state

**Edge Cases:**
- User returns mid-task: Don't interrupt active work
- Multiple short absences: Debounce to avoid repeated summaries
- Very long absences: Cap summary scope (last 24h or 200 entries)
- Background tasks: Distinguish between human-initiated and background activity

**Research Questions:**
1. What's the right idle threshold? (5min too short, 1hr too long)
2. Should summary auto-dismiss after viewing, or require explicit action?
3. How to handle multiple projects with activity?
4. Should action items persist until explicitly resolved?

**Related:**
- Existing LLM summarization infrastructure (TimelineCacheMissGenerator)
- Toast notification system
- System idle time APIs (IOKit, NSEvent)

---

### P4-BLOB-STORAGE: Extract binary content from SQLite to local file storage

**Status:** Not started
**Priority:** P4 (future optimization)
**Effort:** Medium-Large (architecture change)

- [ ] Design and implement content-addressable blob storage for large/binary transcript content

**Problem:**
Claude Code transcripts contain large binary content (base64 images, big file reads, command outputs). Currently stored inline in SQLite which:
- Bloats database size
- Causes memory pressure during parsing (see 35MB buffer limit in HooverEngine)
- Inefficient for repeated access (decode base64 every render)
- Redundant storage (original + transcript + DB)

**Proposed Solution:**
Extract large/binary content to local file storage, store references in DB.

**Design considerations:**
1. **Content-addressable storage** - SHA256 hash as filename for deduplication
2. **Storage location** - `~/Library/Application Support/Contextify/blobs/{hash}`
3. **Detection** - Identify extractable content by size threshold, base64 patterns, MIME hints
4. **DB schema** - Placeholder in content field: `[blob:sha256:abc123]` or separate blob_ref column
5. **Lazy extraction** - Extract on first access, not during initial ingest
6. **Cleanup/GC** - Remove orphaned blobs after transcript deletion
7. **Migration** - Extract existing large entries from DB

**Scope:**
- Images (base64 data URIs)
- Large file read results (>100KB?)
- Large command outputs
- Other binary content

**Research Questions:**
1. What's the right size threshold for extraction vs inline?
2. How to handle the case where blob file is missing (deleted externally)?
3. Should extraction be eager (ingest time) or lazy (first access)?
4. Migration strategy for existing databases with large content?

**Related:**
- TODOS.md#P2-IMAGE-RENDERING - Would benefit from blob storage for efficient image loading
- `app/Sources/ContextifyCore/Database/HooverEngine.swift:531-536` - 35MB buffer limit references this TODO

### P4-TRANSCRIPT-DISPLAY-DELAY: Investigate Delayed/Failed Message Display

**Status:** Not started
**Priority:** P4 (needs investigation, intermittent)
**Effort:** Medium (investigation + potential fixes)
**Found:** 2025-12-08

- [ ] Investigate and fix delayed or failed transcript message display

**Problem:**
User reported new Claude conversations not being picked up. Investigation revealed multiple potential issues in the ingestion pipeline.

**Issues Identified:**

1. **Validator rejects `file-history-snapshot` records (CONFIRMED BUG)**
   - New Claude Code transcripts start with `file-history-snapshot` lacking top-level `uuid`/`timestamp`
   - Validator fails, preflight cache marks transcript as "failed", hoover skips
   - Location: `TranscriptValidator.swift:219-222`

2. **Viewport not updating after entry creation**
   - Logs showed `Added 1 new entries` but `[VIEWPORT-SKIP] Viewport unchanged`
   - Entries created in DB but UI not reflecting them

3. **Streaming messages not displayed (BY DESIGN)**
   - Assistant messages with `stop_reason: null` are buffered until complete
   - May cause perceived lag during active responses

**Reference:**
- `/tmp/transcript-display-delay-investigation-2025-12-08.md` - Full investigation notes
- Log files: `/private/tmp/transcript-queue-monitor-20251208-111748*.log`

**Files to investigate:**
- `app/Sources/ContextifyCore/Database/TranscriptValidator.swift` - validator logic
- `app/Sources/ContextifyCore/Timeline/ConversationMonitor.swift` - viewport updates
- `app/Sources/ContextifyCore/Database/TranscriptParsers.swift` - message parsing

---

### P4-FIRST-RUN-INDEXING: Improve First-Run Indexing Reliability

**Status:** Not started
**Priority:** P4 (App Store reliability, UX polish)
**Effort:** Medium (multiple small changes)
**Found:** 2025-12-09

- [ ] Prevent background indexing cancellation on first run
- [ ] Add completion feedback to indexing progress indicator
- [ ] Suppress progress display for small batches

**Problem:**
Background indexing gets cancelled repeatedly during normal app usage, especially on first run when user is exploring. Log analysis showed 12 of 16 indexing starts were immediately cancelled within 1 minute of activity. This is particularly problematic for App Store builds where users start with an empty database.

**Root Causes:**
1. Every project switch triggers `startBackgroundIndexing()`, which cancels the previous task
2. 5-second delay before work begins means project switches cancel indexing before it starts
3. No distinction between first-run (empty DB) and incremental (mostly indexed)
4. Progress indicator vanishes without completion feedback (never shows "22/22")

**Proposed Solutions:**

1. **First-run protection**
   - Add `hasCompletedInitialIndexing` flag (UserDefaults)
   - Don't cancel background indexing on project switch during first run
   - Higher priority for initial indexing task

2. **Completion feedback**
   - Show "Indexed X projects ✓" briefly (1.5s) instead of immediate disappear
   - Currently `remaining <= 0` immediately sets message to `nil`

3. **Suppress progress for small batches**
   - Don't show "Indexing 3/3 projects..." for fast cycles
   - Threshold: only show for 10+ projects

4. **Debounce indexing start**
   - Wait for activity to settle (2s debounce) before starting
   - Reduces churn from rapid project switches

**Files:**
- `app/Sources/ContextifyCore/Orchestration/AppStateOrchestrator.swift:544-597`
- `Contextify/Contextify/StatusBarViewModel.swift:179-191`

**Reference:**
- `build/notes/todo-support/indexing-progress-ux-research.md` - Full investigation with log analysis

---

### P4-PROJECT-DIRECTORY-ACCESS: Request User Access to Project Directories

**Status:** Not started
**Priority:** P4 (feature enhancement for App Store builds)
**Effort:** Medium (UI + bookmark management)

- [ ] Add UI to request user permission for project directories
- [ ] Store security-scoped bookmarks for granted project directories
- [ ] Enable git branch display and other project features when access granted

**Background:**
App Store (sandboxed) builds can only access transcript directories (`~/.claude/projects/`, `~/.codex/sessions/`) granted via Settings. Project directories (e.g., `~/code/projects/foo/`) are discovered from transcript `cwd` hints but the app has no filesystem access to them.

**Current behavior:**
- Bookmark creation silently fails for discovered projects (sandbox blocks it)
- Git branch shows "—" instead of actual branch
- Git head watching disabled
- Finder reveals may fail silently
- Core transcript display works fine (uses transcript directory access)

**Proposed solution:**
1. Add "Grant Project Access" button in project detail view or settings
2. Use NSOpenPanel to let user select project directory
3. Create and persist security-scoped bookmark
4. Enable git features for projects with granted access
5. Show visual indicator for projects with/without full access

**UX entry points to consider:**
- Settings panel (explicit permission management)
- Git branch InfoPopover (contextual nudge when showing transcript-based branch)
- Project detail view (per-project action)

**Files:**
- `app/Sources/ContextifyCore/HUDCore.swift:707-728` - bookmark handling
- `app/Sources/ContextifyCore/Coordination/StartupCoordinator.swift:490-519` - external project switch
- `Contextify/Contextify/SourceAuthorizationRow.swift` - permission UI pattern to follow

### APPSTORE-CLI-ADMIN: App Store CLI Admin Install with Apple Entitlement

**Goal:** Enable admin privilege CLI installation for App Store builds using Apple's privileged file operations entitlement.

**Background:**
- DMG builds use osascript with admin (implemented in feat/cli-auto-install)
- App Store builds blocked from osascript by sandbox
- Apple provides special entitlement: `com.apple.developer.security.privileged-file-operations`
- Must be requested via special form (not automatically available)
- BBEdit successfully uses this for their App Store version

**Current state:**
- DMG builds: osascript with admin fallback ✅
- App Store builds: ~/bin only (shows PATH warning)

**Implementation plan:**
1. Research entitlement request process
2. Submit request form to Apple
3. If approved: Implement NSWorkspaceAuthorization API
4. Use NSWorkspaceAuthorizationTypeCreateSymbolicLink
5. Update App Store build to offer admin option (like DMG)
6. Update App Store review notes with justification

**Trigger for promotion to P3:**
- App Store user feedback about PATH configuration difficulty
- Support tickets about ~/bin not on PATH
- After v1.0 ships and we validate demand

**Research:** See `build/design/research/ux/appstore-cli-install/README.md`

**Related:**
- Spec: `build/docs/specifications/claude-plugin-auto-install.md` (section 3a)
- Implementation: `Contextify/Contextify/CLICoordinator.swift`

---

## P5 (Research / Exploratory)

### P5-DISTRIBUTION-CHANNELS: Alternative Distribution and Monetization

**Status:** Leads collected
**Priority:** P5 (research, no commitment)
**Effort:** Variable

- [ ] Research RevenueCat for subscription management
- [ ] Research Setapp for distribution

**Leads:**

1. **RevenueCat** - https://www.revenuecat.com/
   - Subscription infrastructure for apps
   - Handles App Store + direct sales + web subscriptions
   - Analytics and subscriber management
   - Could enable "pro tier" without App Store-only billing

2. **Setapp** - https://setapp.com/how-it-works
   - Curated Mac app subscription bundle
   - Users pay monthly, devs get revenue share per usage
   - Exposure to Setapp's subscriber base
   - Alternative to App Store discovery

**Research Questions:**
1. What's the revenue share model for each?
2. Does Setapp require exclusivity or allow parallel App Store presence?
3. RevenueCat integration effort for existing App Store subscriptions?
4. What's the user acquisition potential from Setapp's audience?

**Trigger for promotion:** When ready to explore monetization beyond current free model.

---

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

### P5-APPLE-CAPABILITIES: App ID Capabilities for Future Features

**Status:** Not started (exploratory)
**Priority:** P5 (research - identify which capabilities unlock valuable features)
**Effort:** Variable per capability

- [ ] Research Apple platform capabilities that could enhance Contextify

**Overview:**
Apple App ID capabilities unlock platform integrations. Currently Contextify uses none, but several could enable valuable features.

---

#### Push Notifications

**Capability:** Push Notifications
**Likelihood:** High (near-term)
**Effort:** Medium

**Possible Behaviors:**
- Notify when a long-running Claude Code conversation completes
- Alert when conversation hits an error or tool failure
- "Session idle for 10 minutes - conversation may be waiting for input"
- Daily digest: "You had 5 conversations across 3 projects yesterday"
- Background monitoring alerts when app is closed/menu bar only

**Implementation Notes:**
- Requires APNs certificate setup
- Local notifications sufficient for most use cases (no server needed)
- Could tie into P4-MENUBAR-ICON for unified notification strategy

---

#### App Groups

**Capability:** App Groups
**Likelihood:** Medium (if building companion apps)
**Effort:** Small (entitlement + shared container)

**Possible Behaviors:**
- Share database between Contextify main app and menu bar helper
- Safari extension that shows current project context on contextify.sh
- Keyboard extension for quick transcript search from anywhere
- Share preferences/state across app family
- Spotlight importer as separate target sharing transcript data

**Implementation Notes:**
- Group ID format: `group.sh.contextify`
- Shared UserDefaults suite and container directory
- Enables modular app architecture

---

#### iCloud

**Capability:** iCloud (CloudKit or iCloud Documents)
**Likelihood:** Medium (user-requested feature path)
**Effort:** Large

**Possible Behaviors:**
- Native sync of database across multiple Macs
- Automatic backup of transcript summaries to iCloud
- Continue conversation review on iPad/iPhone (read-only companion app)
- Share project context with team members via iCloud sharing
- Sync settings and preferences across devices

**Implementation Notes:**
- Currently support manual iCloud Drive location for DB file
- Native CloudKit would be more robust (conflict resolution, offline support)
- Significant architecture change from current SQLite-only approach
- Privacy consideration: user transcripts in Apple's cloud

---

#### Sign In with Apple

**Capability:** Sign In with Apple
**Likelihood:** Low (only if adding cloud/team features)
**Effort:** Medium

**Possible Behaviors:**
- Authenticate for cloud sync features
- Team accounts: share project contexts across team
- Web dashboard login (contextify.sh/dashboard)
- License management for paid tiers
- Anonymous usage analytics opt-in tied to account

**Implementation Notes:**
- Requires backend service for token validation
- Not needed for local-only app
- Would enable SaaS pivot if desired

---

#### Siri / App Intents

**Capability:** Siri
**Likelihood:** Medium (differentiator, novelty)
**Effort:** Medium-Large

**Possible Behaviors:**
- "Hey Siri, what was I working on in Claude yesterday?"
- "Summarize my last coding session"
- "How many conversations did I have this week?"
- "Open my Contextify project" (project name)
- "What's the status of my current Claude conversation?"
- Shortcuts app integration for automation workflows

**Implementation Notes:**
- Requires App Intents framework (iOS 16+ / macOS 13+)
- Define intents: GetLastSession, SummarizeProject, OpenProject
- Siri responses need concise, spoken-friendly summaries
- Could integrate with existing LLM summary generation

---

#### Associated Domains

**Capability:** Associated Domains
**Likelihood:** Medium (enables web-to-app flow)
**Effort:** Small

**Possible Behaviors:**
- Click link on contextify.sh to open specific project in app
- Deep links in emails/notifications: `https://contextify.sh/open/project/123`
- Universal links from documentation to relevant app sections
- Share transcript links that open directly in app
- Marketing site "Open in Contextify" buttons

**Implementation Notes:**
- Requires AASA file on contextify.sh server
- URL format: `https://contextify.sh/app/project/{id}`
- Falls back to website if app not installed
- Good for onboarding and marketing funnels

---

#### Fonts

**Capability:** Fonts
**Likelihood:** Low (niche customization)
**Effort:** Small

**Possible Behaviors:**
- Bundle custom monospace fonts optimized for code display
- User-installable fonts for HUD customization
- Typography presets (compact, comfortable, spacious)
- Accessibility: dyslexia-friendly font options

**Implementation Notes:**
- Most users fine with system fonts
- Could differentiate premium/pro tier
- Font licensing considerations for bundled fonts

---

**Research Questions:**
1. Which capabilities have highest user demand?
2. What's the competitive landscape? (Do Cursor/Copilot have Siri integration?)
3. Which capabilities require ongoing infrastructure (push servers, CloudKit)?
4. Priority order for implementation?

**Related:**
- P4-MENUBAR-ICON (complements Push Notifications)
- P5-INVESTIGATE-TRANSCRIPT-PROVIDERS (multi-provider + cloud sync)

---

**End of Roadmap**
