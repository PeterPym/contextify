---
session_id: 7167f5f7-2eb0-47d9-92b7-3cd37532bdf5
date: 2026-03-26
project: contextify
branch: ct-390-v3-polish
status: ready-for-review
---

# Total Recall: Case Study Library

Comprehensive analysis of 38 Total Recall invocations across 5 analysis batches, covering 23 distinct sessions, 9 project directories, and usage spanning from 2026-03-01 to 2026-03-25.

## Executive Summary

| Metric | Value |
|--------|-------|
| Total invocations analyzed | 38 |
| Distinct sessions | 23 |
| Project directories | 9 |
| User-initiated | 31 (82%) |
| AI-initiated | 3 (8%) |
| Agent-delegated | 9 (24%) |
| User requested, AI skipped | 3 (8%) |
| Full success | 22 (58%) |
| Partial success | 5 (13%) |
| Negative proof (valid) | 7 (18%) |
| Failed / indeterminate | 4 (11%) |
| Value delivery rate | 89% (34 of 38 delivered actionable information or confirmed absence) |
| Average searches per invocation | ~2.5 |
| Context drilldown used | 28 of 38 (74%) |

**Classification distribution (invocations may have multiple labels):**

| Category | Count | % of invocations |
|----------|-------|------------------|
| Cross-session continuity | 16 | 42% |
| Decision recall | 13 | 34% |
| Implementation reference | 12 | 32% |
| Knowledge search | 11 | 29% |
| Debugging history | 10 | 26% |
| Negative proof | 9 | 24% |
| Incident forensics | 7 | 18% |
| Session handoff | 5 | 13% |
| Cross-project search | 2 | 5% |
| Counting / audit | 3 | 8% |
| Proof gathering | 1 | 3% |

---

## Category Analysis

### 1. Cross-Session Continuity (42% of invocations)

The most common use case. Users lose track of work done in prior sessions, sometimes across different worktrees, machines, or AI tools (Claude Code vs Codex). Total Recall bridges these gaps.

**Representative cases:**

- **inv-002 (Batch 1):** User asked about "the Fulton House" in a personal administration project. Local grep and bloon returned nothing. TR found a single reference in a February care-coordination session, revealing it was the user's mother's B&B with specific email, booking system, and credential details. This context directly informed a major new project bootstrapping effort triggered by a family death.

- **batch5-001:** User said "we had been working on updating the schema... i thought that work was ~done but have totally lost it." TR found the work was completed the previous day in a Codex CLI session on a different worktree, identified two unmerged atomic commits with exact hashes, and the session proceeded directly to merge and deploy.

- **batch5-005:** User asked "i thought we did a big UX treatment / upgrade for the navigation." TR found the work was scoped and a bloon task created, but the session was sidetracked and implementation never started. The AI provided the task ID, branch name, and path to the design review artifact, enabling immediate pickup.

- **B4-001:** User stated "I've lost my state can you figure out what i was working on last." TR recovered cloud service launch context and the session produced a 4-task queue to resume the work.

**Pattern:** Users frequently have a vague memory ("i thought we did...") but cannot locate the work. TR serves as the definitive oracle for what happened, where it happened, and whether it was finished.

---

### 2. Decision Recall (34% of invocations)

Recovering not just what was decided, but why. This prevents re-litigating settled questions and ensures consistency across long-running projects.

**Representative cases:**

- **inv-006 (Batch 1):** User had a bloon task to pay Delaware franchise tax. Task notes said "$225-450, straightforward." TR found a prior investigation revealing the situation was far more complex: entity was inactive, $172k shown from wrong calculation method, two reports outstanding. TR directly prevented the user from attempting a naive portal payment that would have failed.

- **B4-006:** User was uncertain whether `push_to_canonical=false` in a worktree init script was intentional or a mistake. TR found the explicit decision from March 21 with the reasoning behind both settings, confirming they were correct.

- **B4-004:** User believed pricing had been discussed previously. TR ran 8 queries across 180 days and found the evolution of thinking: from "Free. The whole thing." (Reddit launch, June 2025) to a friend offering $10 for a license, but no final pricing decision was ever made. This was a valuable negative proof combined with a decision timeline.

- **tr-005 (Batch 2):** User asked whether a task spec had been informed by TR. The AI ran TR and recovered a 5-week-old design discussion that added 4 material requirements to the task spec: interactive confirmation, candidate presentation with reasoning, hierarchy-aware rules, and clarification that the work was a behavior change rather than CLI plumbing.

**Pattern:** Decision recall is most valuable when the recovered context contradicts the user's assumptions or the AI's current understanding. In inv-006, TR revealed that a "simple" task was actually complex. In B4-004, it revealed that a "decided" question was actually still open.

---

### 3. Implementation Reference (32% of invocations)

Finding how something was previously built, what approaches were tried, or where specific code/config lives.

**Representative cases:**

- **batch3-1:** User was debugging why binary patcher tier 1 discovery was failing. TR found a prior session where structural fallback auto-discovery had been implemented and tested. The recovered context led directly to fixing patch-defs.json anchors and regexes, achieving 8/8 discovery and 7/7 successful patch application.

- **B4-007:** User believed a cross-repo wt-sync feature had been implemented but could not find it. TR located the specific file (.claude/skills/wt-sync.md), a project-level skill override that wrapped the global wt-sync skill with contextify-cloud verification.

- **B4-010:** AI-initiated search to find the full cloud product specification. TR returned comprehensive prior discussions about planned dashboard pages, feature requirements, and design decisions, directly informing what needed to be built.

**Pattern:** Implementation reference searches frequently start vague ("i thought we addressed this") and narrow through TR results to specific files, commits, and approaches.

---

### 4. Knowledge Search (29% of invocations)

"What do we know about X?" searches across accumulated conversation history.

**Representative cases:**

- **inv-001 (Batch 1):** User asked whether any prior conversations discussed the QA-to-QE professional title rename. TR ran 4 searches, correctly identified and discarded false positives (regex `-qE` flag, project QA testing activity), and confirmed zero relevant history. A clean negative proof.

- **batch5-002:** User and AI discussed expanding a cloud backend as a general platform for multiple AI CLI tools. The AI noted this vision "wasn't captured anywhere in docs or tasks." TR found the original conversation where the user had explicitly articulated the hosted private instance vision with verbatim quotes.

- **B4-003:** User asked "use an agent and /total-recall to see our plans for 1.5.0." Agent returned a comprehensive release plan: v1.5.0 = Cloud Launch (ct-389), with the guiding principle "We can't release without pricing; we can't announce something that can't be bought."

**Pattern:** Knowledge searches are the broadest category. They range from topical research to architectural vision recovery to release planning context.

---

### 5. Debugging History (26% of invocations)

Tracing when issues appeared, finding prior investigations, and recovering diagnostic context.

**Representative cases:**

- **inv-005 (Batch 1):** A pre-commit git hook blocked certain paths from being committed. The hook was in .git/hooks/ (untracked, invisible to git log). TR found the original session (transcript CC2EFA26, ~Feb 16, 2026) that created the hook, and the reasoning: docs/ was blocked preemptively when there was a plan to push to GitHub.

- **B4-009:** User was frustrated that the AI was working from an outdated deployment runbook with the wrong server IP. TR found the correct IP (174.138.94.110 vs the old 143.198.70.216 in the runbook) and the correct SSH key path, correcting a discrepancy that would have blocked deployment.

- **B4-011:** Unexpected Sentry monitoring files appeared on the production server. TR identified the specific Codex CLI session that had added them, confirmed the work was complete and validated (smoke tests passed, email alerts confirmed), and the branch was merged.

**Pattern:** Debugging history is often triggered by something unexpected appearing in the codebase or environment. TR serves as the forensic trail to explain provenance.

---

### 6. Negative Proof (24% of invocations)

Confirming something was NOT discussed, NOT completed, or does NOT exist in history. This is a distinct and underappreciated value mode.

**Representative cases:**

- **B4-013:** User believed ct-361 (duplicate device registrations) had been resolved. TR confirmed it had NOT been resolved, with no evidence of completion in any session. Task correctly left open.

- **B4-004:** User believed pricing had been decided. TR found the evolution of thinking but confirmed no final pricing call was ever made.

- **batch5-004:** User asked whether a code review loop had already been run, to avoid doing it twice. TR found it HAD been run (success rather than negative proof), preventing duplicate work.

- **batch3-4:** Three searches returned zero results for "lost patcher work." This was a genuine negative proof: the work either used different terminology or occurred outside the indexed window.

**Pattern:** Negative proofs are often as valuable as positive hits. They give confidence to proceed (knowing the gap is an oversight, not a deliberate decision) or to deprioritize (knowing the task is genuinely incomplete).

---

### 7. Incident Forensics (18% of invocations)

Tracing chains of events across sessions, often involving unexpected state changes or system behavior.

**Representative cases:**

- **inv-003 (Batch 1):** User was drafting a message to a business partner about inability to pay Delaware franchise tax. They needed the exact error text from the state website that they had seen in a prior session. TR found the exact text: entity file 5759110 shown as inactive, two outstanding reports, and $172,758.28 displayed using the wrong calculation method. The user quoted this directly in their message.

- **tr-006 (Batch 2):** During debugging of a spurious "cc-" prefixed project in a task manager, TR searched for the creation event. Returned 80 results but the "cc-" prefix was too common a substring (abbreviation for Claude Code, entry IDs, filenames). The specific creation event was not isolated, illustrating a precision limitation with short common tokens.

- **B4-008 / B4-009:** Two sequential invocations to find the correct cloud server IP and SSH credentials. The first found the correct IP but the assistant initially tried the wrong one from an outdated runbook. The second, prompted by user frustration, confirmed the correct details and corrected the deployment script.

**Pattern:** Forensic searches require the most precision. Short or ambiguous terms ("cc-") produce high volume but low signal. Multi-round refinement is common.

---

### 8. Session Handoff (13% of invocations)

Explicitly bootstrapping a new session with context from a prior one, often across worktrees or AI tools.

**Representative cases:**

- **batch5-005:** TR found that a navigation UX redesign had been scoped but never implemented. User immediately said "I do want you to pick up the work" and provided a handoff document from the other AI. TR results formed the seed context for the handoff.

- **batch5-003:** Cross-worktree session audit. User asked TR to check all 6 worktrees (wb1-wb4, liquid-glass, worker-bee) to identify wrap-up tasks. This required 10+ search/context commands plus fallback to git and bloon CLIs.

- **B4-001:** User had lost session state and wanted to resume cloud service work. TR recovered the cloud service context and the session produced a prioritized 4-task queue to resume.

**Pattern:** Session handoff is the most operationally critical use case. It directly reduces "where was I?" startup friction that compounds across weeks of parallel worktree development.

---

### 9. Counting / Audit (8% of invocations)

Systematic verification across a set of items.

**Representative case:**

- **B4-015:** User asked to validate all open P1 tasks to find any that could be closed "for free." Two parallel agents each triaged 10-12 tasks using TR as the primary verification tool. Result: recent P1s were all genuinely open, but a bonus actionable bug was identified (ct-456) and immediately fixed.

**Pattern:** Batch triage is an emerging use pattern enabled by agent delegation. It turns TR from a point-query tool into a systematic audit tool.

---

## Cross-Cutting Analysis

### Value Delivery Rate: 89%

Of 38 invocations, 34 delivered actionable information. The 4 that did not:
- 1 was preempted by filesystem discovery (tr-001, Batch 2)
- 1 had its agent cut off by context exhaustion (batch3-5)
- 2 were indeterminate due to transcript excerpt truncation (tr-004, Batch 2; batch3-5)

Even "zero results" cases delivered value when they constituted negative proof (confirming absence is itself actionable).

### Common Failure Modes

1. **FTS5 hyphen tokenization** (3 batches): Hyphenated terms like "cli-ai-setup" or "review-loop" are split on hyphens by FTS5. "ai" is then interpreted as a column reference, producing "no such column: ai" errors. Workarounds include quoting phrases ("review loop") or switching to project-scoped activity queries.

2. **Narrow date windows** (Batch 3): Some searches used --days 30 or --days 60 for "lost work" that could have occurred at any time. Widening to --days 365 would have improved recall.

3. **Short/ambiguous tokens** (Batch 2, tr-006): Searching for "cc-" produced 80 results because "cc" appears as an abbreviation, in entry IDs, and in filenames. Precision suffers with common substrings.

4. **Self-referential hits** (Batch 1, inv-004): The current session's own mention of a term gets indexed and returned as a result, creating false positive noise.

5. **Cross-project contamination** (Batch 3, batch3-3): Searching for "gcal" returned results from an unrelated project (GheeCalendar). Project scoping did not fully isolate results.

6. **AI skipping the skill** (3 cases across batches 3-4): User explicitly said "use /total-recall" but the AI answered via direct CLI calls, bloon, or git without invoking the skill. This may produce correct answers but bypasses the skill's structured search strategy.

### Friction Points

1. **"Multiple Contextify installs detected" warning**: Appeared in every invocation in Batch 1. Consistent UX noise that does not affect results but adds visual clutter.

2. **--project flag defaulting to cwd**: The `--project` flag sometimes defaults to the current working directory project rather than looking up by name, requiring fallback to `--project-id` with explicit UUID.

3. **Query construction anti-patterns**: AI agents frequently give up after 1-2 failed searches rather than widening date windows, trying synonyms, or removing restrictive AND clauses. Batch 3 had the poorest query construction quality with 3 of 6 rated "poor."

4. **Agent delegation overhead**: Agent-delegated searches consumed 60-226K tokens. While thorough, the cost-per-query is high for simple lookups.

### Project and Domain Distribution

| Domain | Invocations | % |
|--------|-------------|---|
| macOS developer tool (Contextify) | 15 | 39% |
| CLI tooling project | 6 | 16% |
| Personal administration | 6 | 16% |
| Task manager (Bloon) | 2 | 5% |
| Personal/misc | 4 | 11% |
| Consulting project | 1 | 3% |
| Multiple worktrees (cross-cutting) | 4 | 11% |

Total Recall is used across both professional development and personal administration, with the heaviest usage in the developer's primary product codebase.

---

## Marketing Insights

### Top 10 Cases for Marketing

1. **inv-006 (Batch 1):** "Task notes said $225. Reality was $172K." TR caught a dangerously incomplete task description before the user attempted a payment that would have failed. (Decision recall, risk prevention)

2. **batch5-005:** "I thought we did a big UX treatment." TR found the work was scoped but never implemented, provided the task ID, branch name, and design review artifact, enabling immediate cross-session pickup. (Session handoff, continuity)

3. **inv-003 (Batch 1):** "Do you have the actual text I encountered on the web?" TR recovered the exact Delaware state website error text from a prior session, which the user quoted verbatim in a message to their business partner. (Precision recall)

4. **tr-005 (Batch 2):** "Make sure valuable information makes its way in." TR recovered a 5-week-old design discussion that added 4 material requirements to a task spec. (Decision recall, spec enrichment)

5. **batch3-1:** "i thought we did that." TR found the prior session where structural fallback discovery was implemented, directly unblocking a fix that achieved 8/8 patch discovery. (Implementation reference, unblocking)

6. **B4-011:** "Can you figure out where they came from?" Unexpected Sentry files on a production server traced to a specific Codex CLI session. Work was confirmed complete, branch merged safely. (Incident forensics)

7. **inv-002 (Batch 1):** "The Fulton House." A two-word query that surfaced B&B ownership details, email, booking system, and credentials from a care-coordination session, bootstrapping a major new project after a family death. (Cross-session continuity, life event)

8. **B4-004:** "I thought we discussed pricing previously." 8 queries across 180 days found no final pricing call, but traced the evolution from "free everything" to considering paid tiers. (Decision archaeology, negative proof)

9. **batch5-001:** "i have totally lost it." Lost schema update work found: completed the previous day in a different worktree by a different AI tool, two unmerged commits with exact hashes. Session proceeded directly to merge. (Cross-session continuity, cross-tool)

10. **B4-015:** "validate the P1s and see if we can close a bunch for free." Two parallel agents triaged 20+ tasks using TR. All genuinely open, but a bonus bug was found and immediately fixed. (Batch audit, systematic verification)

### Before/After Scenarios

**Before Total Recall:**
- "I know we discussed this, but I can't remember what we decided."
- "Was this task already done? Let me re-investigate from scratch."
- "Where is that config file? I'll search the filesystem for 20 minutes."
- "The AI set up this server last week but I don't remember the IP."
- "This task says $225 but something feels off. I'll just try the portal."

**After Total Recall:**
- The exact decision, with reasoning, recovered in under a minute.
- Task completion status confirmed or denied with evidence.
- File path, commit hash, or branch name retrieved from conversation history.
- Server IP, SSH key path, and deployment details recovered with provenance.
- Prior investigation surfaces showing the real complexity, preventing a costly mistake.

---

## Product Improvement Opportunities

See [product-improvements.md](./product-improvements.md) for the full prioritized list. Key themes:

1. **FTS5 hyphen tokenization** must be fixed. Multiple batches hit this. It blocks the most natural query patterns.
2. **Query construction guidance** should be embedded in the skill. AI agents construct poor queries too often.
3. **"Multiple installs" warning** should be suppressed or moved to a diagnostic mode.
4. **Self-referential hit filtering** would reduce noise from the current session's own entries appearing in results.
5. **Date window defaults** should be wider (365 days) for exploratory searches, narrower only when the user specifies recency.
