# Project Chronicle: Continuous Development Narrative Synthesis

## Overview

Project Chronicle is a background service that continuously analyzes conversation transcripts to build a higher-level narrative of development work. It captures the organic, often nested nature of how development actually unfolds - where pursuing one goal reveals prerequisites, which expose bugs, which require architectural changes - creating a queryable "development story" that helps developers (and AI agents) quickly understand how the project arrived at its current state.

### The Problem

Modern AI-assisted development has fundamentally changed the productivity/context tradeoff:

1. **Velocity is dramatically higher** - More code, more architectural decisions, more pivots happen per hour than ever before
2. **The "flow state" has moved up the stack** - Developers now flow at the design/architecture level, not the line-by-line level
3. **Interruption cost has inverted** - Losing your mental model of a multi-layer discovery chain is harder to recover than losing your model of 50 lines of code
4. **Memory is unreliable** - At this velocity, developers cannot reliably reconstruct "what was I working on and why?" even after a short break

### The Insight

Handoff documents created for practical continuation (conversations exceeding context length) accidentally became the only reliable archaeology of development intent. They captured:
- The narrative arc, not just the code changes
- Tangents and their relationship to main work
- Decisions and their reasoning
- Failed approaches (what NOT to repeat)
- The "russian doll" nesting of discoveries

But handoffs are:
- Manual (require explicit `/handoff` invocation)
- Point-in-time (snapshot, not continuous)
- Single-session (don't automatically link across conversations)

### The Vision

Project Chronicle automatically and continuously builds the narrative that handoffs capture manually. Every conversation, every exchange, every `/clear` continuation feeds into an evolving understanding of what the developer is doing and why.

---

## Core Concepts

### Narrative Arc

A coherent thread of work toward a goal. Arcs have:
- **Intent**: What the developer is trying to accomplish
- **Strategic Context**: Why this work matters in the bigger picture
- **State**: Active, completed, blocked, abandoned
- **Lineage**: Parent arc (if this was discovered while working on something else)

### Discovery Chain

When working on Arc A reveals that Arc B must be completed first, which reveals Bug C, which requires Refactor D - this is a discovery chain. The classic "russian doll" pattern:

```
Arc: Add user authentication
  └─ Discovery: Need session management first
       └─ Discovery: Session store has race condition
            └─ Discovery: Need to refactor state sync
```

### Signpost

A significant moment in the narrative:
- **Decision**: A choice was made (and why)
- **Discovery**: Something unexpected was found
- **Pivot**: Direction changed
- **Milestone**: Something completed
- **Blocker**: Progress stopped (and why)

### Transcript Continuity

Multiple transcripts that are part of the same narrative thread:
- `/clear` followed by continued work
- Compaction followed by continued work
- Same project, close timestamps, related content
- Explicit references ("continuing from earlier...")

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Project Chronicle                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │  Transcript  │───▶│   Narrative  │───▶│   Chronicle  │  │
│  │   Watcher    │    │   Analyzer   │    │    Store     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                   │                    │          │
│         │                   ▼                    │          │
│         │           ┌──────────────┐             │          │
│         │           │    Local     │             │          │
│         └──────────▶│     LLM      │◀────────────┘          │
│                     │  (Apple AI)  │                        │
│                     └──────────────┘                        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Transcript Watcher

Monitors the existing Contextify transcript ingestion pipeline:
- Receives notifications when new entries are ingested
- Detects transcript boundaries (new conversation started)
- Detects continuity signals (`/clear`, compaction, time gaps)
- Extracts git context from conversation content (branch names, commit references mentioned)

### Narrative Analyzer

The LLM-powered analysis engine:
- Processes new exchanges incrementally
- Maintains conversation-level understanding
- Detects arc boundaries (new goal, topic shift)
- Identifies signposts (decisions, discoveries, pivots)
- Links related transcripts into continuous threads
- Detects discovery chains (nested arcs)

### Chronicle Store

Persists the derived narrative data:
- Arcs with their relationships (parent, discovered-from, blocks)
- Signposts with timestamps and transcript references
- Transcript continuity links
- Generated narrative documents

### Local LLM Integration

Uses Apple Intelligence (macOS 26+) for on-device processing:
- Privacy-preserving (no data leaves device)
- Low-latency for incremental processing
- Structured output for narrative extraction

---

## Processing Pipeline

### 1. Exchange Ingestion

When a new transcript entry is ingested:

```swift
func onEntryIngested(entry: TranscriptEntry, transcript: Transcript) {
    // Queue for narrative analysis
    analysisQueue.enqueue(AnalysisTask(
        entry: entry,
        transcript: transcript,
        project: transcript.projectId
    ))
}
```

### 2. Continuity Detection

Determine if this transcript continues a previous thread:

**Signals for continuity:**
- Previous transcript in same project ended with `/clear` command
- Previous transcript was compacted (content preserved but context reset)
- Time gap < threshold (e.g., 30 minutes) AND content references previous work
- Explicit continuation phrases ("continuing from...", "picking up where...")

**Signals for new thread:**
- Different project
- Large time gap with no continuation signals
- Explicit new-work phrases ("starting fresh", "new task")

### 3. Content Analysis

For each exchange or batch of exchanges, query the LLM:

```
Given this conversation exchange in the context of project "{project_name}":

<exchange>
{user_message}
{assistant_response}
</exchange>

<recent_context>
{last_N_exchanges_summary}
</recent_context>

<current_arc>
{active_arc_description_if_any}
</current_arc>

Analyze this exchange and respond with structured JSON:

1. arc_status: Is this continuing the current arc, starting a new arc, or discovering a nested arc?
2. arc_update: If new/nested, what is the intent and strategic context?
3. signposts: Any decisions made, discoveries found, pivots taken, milestones reached, or blockers encountered?
4. git_context: Any branch names, commit messages, or PR references mentioned?
5. continuation_confidence: How confident are you this is the same work thread as previous exchanges?
```

### 4. Narrative Synthesis

Periodically (or on-demand), synthesize the accumulated analysis into narrative documents:

**Per-Arc Narrative:**
```markdown
# Arc: {intent}

**Strategic Context:** {why_this_matters}
**Status:** {active|completed|blocked|abandoned}
**Started:** {timestamp}
**Parent Arc:** {if_discovered_from_another}

## Timeline

- {timestamp}: Started work on {description}
- {timestamp}: Decision - {what_and_why}
- {timestamp}: Discovered need for {nested_arc}
  - [Arc: {nested_intent}]
- {timestamp}: Returned from {nested_arc}
- {timestamp}: Milestone - {what_completed}

## Key Decisions

1. **{decision}** - {reasoning}
   - Revisit if: {conditions}

## Discoveries

1. {what_was_found} - led to {consequence}

## Related Transcripts

- {transcript_id} ({timestamp_range})
- {transcript_id} ({timestamp_range})
```

**Project Chronicle (high-level):**
```markdown
# Project Chronicle: {project_name}

**Last Updated:** {timestamp}
**Active Arcs:** {count}
**Recent Activity:** {summary}

## Current Focus

{description_of_active_work}

## Recent Arc History

### {arc_intent} ({status})
{brief_summary}
- Key decisions: {list}
- Discovered: {nested_arcs}

### {previous_arc} ({status})
...

## Development Patterns

{observations_about_how_work_flows}
- Tendency toward {pattern}
- Common discovery chain depth: {N}
- Typical arc duration: {range}
```

---

## Data Model

### ChronicleArc

```swift
struct ChronicleArc: Codable, Identifiable {
    let id: String
    let projectId: String

    // Core identity
    var intent: String              // What is being attempted
    var strategicContext: String?   // Why it matters
    var status: ArcStatus           // active, completed, blocked, abandoned

    // Relationships
    var parentArcId: String?        // If discovered from another arc
    var discoveredFromEntryId: String?  // The entry where this was discovered
    var blockedByArcId: String?     // If blocked by another arc

    // Temporal
    var startedAt: Date
    var completedAt: Date?
    var lastActivityAt: Date

    // Content links
    var transcriptIds: [String]     // All transcripts involved
    var entryIdRange: (first: String, last: String)?
}

enum ArcStatus: String, Codable {
    case active
    case completed
    case blocked
    case abandoned
}
```

### ChronicleSignpost

```swift
struct ChronicleSignpost: Codable, Identifiable {
    let id: String
    let arcId: String
    let entryId: String             // The transcript entry where this occurred

    var kind: SignpostKind
    var summary: String             // Brief description
    var detail: String?             // Extended explanation
    var timestamp: Date

    // For decisions
    var reasoning: String?          // Why this choice was made
    var revisitConditions: String?  // When to reconsider

    // For discoveries
    var consequenceArcId: String?   // Arc spawned by this discovery
}

enum SignpostKind: String, Codable {
    case decision
    case discovery
    case pivot
    case milestone
    case blocker
    case resolution
}
```

### TranscriptContinuity

```swift
struct TranscriptContinuity: Codable {
    let fromTranscriptId: String
    let toTranscriptId: String
    var continuitySignal: ContinuitySignal
    var confidence: Double          // 0.0 to 1.0
}

enum ContinuitySignal: String, Codable {
    case clearCommand       // /clear was used
    case compaction         // Context was compacted
    case timeProximity      // Close in time, related content
    case explicitReference  // Explicitly mentions continuing
}
```

---

## Integration Points

### Timeline Augmentation

The existing timeline view can be enhanced with Chronicle data:
- Show arc boundaries as visual separators
- Display signpost badges on relevant entries
- Indicate discovery chain depth (nesting level)
- Link to arc narrative documents

### New Project Chronicle View

A dedicated view showing the high-level narrative:
- Arc timeline (not entry-level, but goal-level)
- Discovery chain visualization
- Signpost highlights
- Patterns and observations

### Handoff Integration

Chronicle can inform the `/handoff` skill:
- Auto-populate "Main Task" from active arc intent
- Auto-populate "Strategic Context" from arc context
- Generate "Work Completed" from recent signposts
- Generate "Pending Tasks" from blocked/active arcs
- Generate "Decisions Made" from decision signposts

### Future: Chronicle Query Skill

A new skill for querying chronicle data:
```
/chronicle "how did we get to the current architecture?"
/chronicle --arc "authentication" --signposts
/chronicle --since "yesterday" --discoveries
```

---

## Team Aggregation (Future Vision)

When multiple developers work on the same project, their individual chronicles can be aggregated:

### Individual Chronicle Streams

Each developer's Contextify instance builds their own chronicle:
- Their arcs, signposts, discoveries
- Their narrative of the work

### Aggregation Service

A service (could be self-hosted or cloud) that:
- Receives chronicle exports from team members
- Correlates arcs across developers (same intent = same arc?)
- Identifies:
  - **Parallel work**: Multiple people on independent arcs
  - **Collaboration**: Multiple people contributing to same arc
  - **Conflicts**: Contradictory decisions or duplicate effort
  - **Dependencies**: One person's arc blocks another's
  - **Handoffs**: Work transferred between developers

### Team Chronicle View

Shows the unified narrative:
```
Week of Dec 16-22:

[Alice] Arc: Sidechain Ingestion
  └─ Discovery: Filter coupling bug
       └─ [Bob] Arc: EntryFilter Architecture (handed off)
            └─ Completed, returned to Alice

[Charlie] Arc: Search Performance
  ├─ Parallel to Alice's work
  └─ Discovered same coupling bug independently (flagged as duplicate)

[Team] Decision: Use aggregate subqueries for stats
  └─ Made by Bob, adopted by all
```

### Cohesion Analysis

The aggregated chronicle can answer:
- Is the team working toward coherent goals?
- Are there unrecognized dependencies?
- Is effort being duplicated?
- Are decisions being made consistently?
- Where are the integration points and risks?

---

## Implementation Phases

### Phase 1: Foundation

**Goal:** Prove the concept with document generation

- [ ] Transcript watcher integrated with ingestion pipeline
- [ ] Apple Intelligence integration for analysis
- [ ] Basic arc detection (new work vs. continuation)
- [ ] Signpost extraction (decisions, discoveries)
- [ ] Generate per-session narrative documents to `/tmp/`
- [ ] Validate output quality and usefulness

**Success Criteria:**
- Generated narratives are accurate and useful
- Can reconstruct "what was I working on?" from output
- Processing is fast enough to be near-real-time

### Phase 2: Persistence & Continuity

**Goal:** Build the data model and cross-session linking

- [ ] Chronicle database schema (arcs, signposts, continuity)
- [ ] Transcript continuity detection (`/clear`, compaction, etc.)
- [ ] Arc relationship tracking (parent, discovered-from)
- [ ] Discovery chain reconstruction
- [ ] Project-level chronicle generation

**Success Criteria:**
- Arcs correctly span multiple transcripts
- Discovery chains are accurately represented
- Can query "how did we get here?" for any arc

### Phase 3: Integration

**Goal:** Surface chronicle data in the app

- [ ] Timeline view augmentation (signpost badges, arc separators)
- [ ] New Project Chronicle view
- [ ] Handoff skill auto-population from chronicle
- [ ] Chronicle export (for team aggregation)

**Success Criteria:**
- Developers find the integrated views useful
- Handoff quality improves with auto-population
- Data is exportable in a useful format

### Phase 4: Team Aggregation

**Goal:** Multi-developer chronicle synthesis

- [ ] Chronicle export format specification
- [ ] Aggregation service (self-hosted first)
- [ ] Cross-developer arc correlation
- [ ] Conflict/duplicate detection
- [ ] Team chronicle view

**Success Criteria:**
- Team can see unified development narrative
- Coordination issues are surfaced
- Decisions are tracked across team

---

## Open Questions

1. **Arc Granularity**: How fine-grained should arcs be? A single feature? A single bug fix? A single investigation? Probably need heuristics and possibly user correction.

2. **LLM Cost**: Apple Intelligence is free, but how much processing can we realistically do per exchange? May need to batch or summarize.

3. **Retroactive Analysis**: Should Chronicle analyze historical transcripts, or only process going forward? Backfill could be expensive but valuable.

4. **User Correction**: Should users be able to correct arc detection, merge arcs, split arcs? How does this interact with continuous processing?

5. **Privacy for Team Aggregation**: How do we aggregate across developers while preserving appropriate privacy? Not all work should be visible to all team members.

6. **Git Integration Depth**: We're gleaning git info from conversations, but should we eventually integrate directly for richer correlation?

---

## Appendix: Inspiration from Handoff Template

The `/handoff` skill's `--deep` mode template captures the structure we want to automate:

```markdown
# Continuation: {brief task description}

## Main Task                    → Arc intent
## Strategic Context            → Arc strategic context
## Tangents                     → Discovered arcs with relationship
## Pending Tasks                → Active/blocked arcs
## Work Completed               → Milestone signposts
## Next Steps                   → Arc continuation guidance
## Decisions Made               → Decision signposts with reasoning
## Failed Approaches            → Pivot signposts
## Blockers / Waiting On        → Blocker signposts
## Task Lineage                 → Discovery chain

```

Chronicle automates the continuous creation of this structure, updating it with every exchange rather than requiring manual invocation.

---

## Appendix: LLM Processing Methodology (Context Window Constraints)

Local LLMs (Apple Intelligence) have limited context windows - likely 4-8K tokens. This section describes how to build narrative understanding incrementally using many small calls.

### Core Pattern: State + Delta

Instead of "analyze everything", do "update state with this new thing":

```
┌─────────────────────────────────────────────────┐
│           Persistent Narrative State            │
│  - Current arc (intent, context, status)        │
│  - Recent exchanges (rolling window of ~5)      │
│  - Open signposts (decisions pending, blockers) │
│  - Arc stack (nested discoveries)               │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│              New Exchange Arrives               │
│  - User message + Assistant response            │
│  - ~500-2000 tokens typically                   │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│              LLM Call (~3-4K context)           │
│  Input:                                         │
│    - Compressed state (~1K tokens)              │
│    - New exchange (~1K tokens)                  │
│    - Structured prompt (~500 tokens)            │
│  Output:                                        │
│    - State delta (what changed)                 │
│    - Signposts detected                         │
│    - Arc updates                                │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│              Apply Delta to State               │
│  - Update arc if changed                        │
│  - Push/pop arc stack if discovery/return       │
│  - Record signposts                             │
│  - Slide rolling window                         │
└─────────────────────────────────────────────────┘
```

### Hierarchical Summarization

Build summaries at multiple levels, each compressing the level below:

```
Level 0: Raw exchanges (full content, not stored long-term)
    ↓ LLM summarizes
Level 1: Exchange summaries (~50 tokens each)
    ↓ LLM synthesizes every ~10 exchanges
Level 2: Session summaries (~200 tokens)
    ↓ LLM synthesizes when arc completes
Level 3: Arc summaries (~300 tokens)
    ↓ LLM synthesizes periodically
Level 4: Project narrative (~1000 tokens)
```

Each level is queryable. Higher levels fit in context easily.

### Specific LLM Call Types

**1. Exchange Analysis** (runs on every new exchange)
```
Context: ~2K tokens
- Current arc summary (200 tokens)
- Last 3 exchange summaries (150 tokens)
- New exchange (1000 tokens)
- Prompt (200 tokens)

Output: JSON
- exchange_summary: string (50 tokens)
- arc_status: "continuing" | "pivoting" | "discovering" | "completing"
- signposts: [{kind, summary}]
- arc_update: {intent?, context?} if changed
```

**2. Arc Synthesis** (runs when arc completes or on-demand)
```
Context: ~3K tokens
- All exchange summaries for this arc (may need chunking if >20)
- Signposts recorded
- Child arc summaries (if discoveries occurred)

Output: Markdown
- Arc narrative document
```

**3. Continuity Detection** (runs when new transcript starts)
```
Context: ~2K tokens
- Last transcript's final state
- New transcript's first 2-3 exchanges
- Time gap, project match

Output: JSON
- is_continuation: boolean
- confidence: 0-1
- reasoning: string
```

**4. Project Synthesis** (runs periodically or on-demand)
```
Context: ~4K tokens
- All arc summaries (chunked if needed)
- Recent signposts
- Patterns observed

Output: Markdown
- Project chronicle document
```

### Chunking Strategy for Large Histories

When arc has many exchanges (>20):

```
Chunk 1: exchanges 1-10 → summary A
Chunk 2: exchanges 11-20 → summary B
Chunk 3: exchanges 21-30 → summary C
...
Final: summaries A,B,C,... → arc narrative
```

Each chunk fits in context. Final synthesis combines chunk summaries.

### RAG for Historical Queries

When current analysis needs historical context:

1. Embed the query/current state
2. Search arc/signpost embeddings
3. Retrieve top-k relevant items
4. Include in context for LLM call

Example: Detecting if current work relates to previous arc
```
Query: "working on filter architecture"
Retrieved: Arc "SIDECHAIN-INGESTION" (similarity 0.8)
Context includes: That arc's summary
LLM can now detect: "This is related to previous sidechain work"
```

### State Persistence

The narrative state persists in SQLite:
- Survives app restarts
- Survives conversation context limits
- Can be queried independently of LLM

LLM calls are stateless - all context comes from persistent state + new input.

### Summary

This approach means:
- No single call needs the full history
- Each call is fast (small context)
- State accumulates over time
- Narrative quality improves with more data
- Works within Apple Intelligence constraints

---

## References

- `/handoff` skill template (for narrative structure inspiration)
- Contextify transcript ingestion pipeline (integration point)
- Apple Intelligence documentation (LLM integration)
- Existing timeline view (augmentation target)
