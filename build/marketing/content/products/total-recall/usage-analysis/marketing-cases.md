---
session_id: 7167f5f7-2eb0-47d9-92b7-3cd37532bdf5
date: 2026-03-26
project: contextify
branch: ct-390-v3-polish
status: ready-for-review
---

# Total Recall: Marketing Cases

Top 15 cases from 38 invocations, formatted for marketing use. Each case includes the problem scenario, what Total Recall delivered, the pattern it represents, and the audience segment it resonates with.

Privacy: all cases use generic project descriptions rather than specific client or product names.

---

## 1. "The Task Said $225. The Reality Was $172,000."

**Before:** A developer had a task to pay a routine franchise tax. The task notes said "$225-450, straightforward, just go to the portal and pay." They were about to navigate to the payment portal and submit.

**After:** Total Recall found a prior investigation from weeks earlier revealing the entity was inactive, the portal showed $172,758.28 from the wrong calculation method, and two reports needed filing before any payment could succeed. The developer rewrote their approach entirely, prepared a list of questions for their accountant, and avoided a failed payment that would have cost hours of debugging.

**Pattern:** Decision recall / Risk prevention
**Audience:** Solo dev, anyone managing business operations alongside code
**Source:** inv-006 (Batch 1)

---

## 2. "I Thought We Did a Big UX Upgrade. Where Did It Go?"

**Before:** A developer vaguely remembered completing a navigation redesign for their web dashboard. They could not find any code changes, commits, or branches that matched. Had the work been done? Lost? Still planned?

**After:** Total Recall found the work: it was scoped in a prior session, a task was created, a branch was started, and a design review was written to a temporary file. But the implementation session was sidetracked and the actual code was never written. TR provided the exact task ID, branch name, and path to the design artifact. The developer picked up the work immediately with full context.

**Pattern:** Cross-session continuity / Session handoff
**Audience:** Solo dev managing multiple parallel workstreams
**Source:** batch5-005 (Batch 5)

---

## 3. "Give Me the Exact Text I Saw on That Government Website"

**Before:** A developer was drafting a message to a business partner about a tax filing problem. They needed to quote the exact error text they had seen on a state government website weeks earlier, but the website text was not saved anywhere and the browser session was long gone.

**After:** Total Recall found the exact website text from a prior AI conversation where they had discussed the error. The entity status, file number, outstanding report years, and incorrect tax calculation were all recovered verbatim. The developer pasted the recovered text directly into their message.

**Pattern:** Precision recall / Incident documentation
**Audience:** Anyone who uses AI as a working companion for non-code tasks
**Source:** inv-003 (Batch 1)

---

## 4. "Make Sure Our Old Design Ideas Make It Into the New Spec"

**Before:** A developer was writing a task specification for an AI-driven focus feature. They had a nagging feeling they had discussed the design in detail weeks earlier but could not find those notes anywhere.

**After:** Total Recall recovered a 5-week-old design discussion that contained 4 specific requirements never captured in any document: interactive confirmation before closing items, candidate presentation with reasoning, hierarchy-aware auto-advance rules, and clarification that the work was a behavior change rather than plumbing. All 4 requirements were added to the spec.

**Pattern:** Decision recall / Spec enrichment
**Audience:** Solo dev, team lead reviewing specifications
**Source:** tr-005 (Batch 2)

---

## 5. "I Thought We Fixed That. Why Is Patching Still Failing?"

**Before:** A developer's binary patcher was failing to discover two specific patches. They believed this had been fixed in a prior session but the fix was not in the current code.

**After:** Total Recall found the session where "structural fallback auto-discovery" was designed and implemented. The AI recovered the approach (auto-generate regex from search templates when hand-written patterns fail), identified that the current anchors were pointing 2MB away from the actual functions, and applied the fix. Result: 8 of 8 patches discovered, 7 of 7 applied successfully.

**Pattern:** Implementation reference / Debugging
**Audience:** Solo dev maintaining complex tooling
**Source:** batch3-1 (Batch 3)

---

## 6. "Where Did These Monitoring Files Come From?"

**Before:** Unexpected Sentry error monitoring files appeared on a production server. No one in the current session had added them. Were they leftover from a test? Partially complete? Safe to commit?

**After:** Total Recall traced the files to a specific automated session (Codex CLI) that had implemented production error monitoring as a tracked task. The work was confirmed complete: Sentry was live, smoke tests passed, email alerts were confirmed working. The branch was safely merged and the server state cleaned up.

**Pattern:** Incident forensics / Cross-tool provenance
**Audience:** Solo dev running multiple AI tools, team lead tracking agent work
**Source:** B4-011 (Batch 4)

---

## 7. "Two Words Unlocked an Entire Family Project"

**Before:** A developer asked their AI about "the Fulton House." Local file search, task search, and code search all returned nothing. The AI concluded "no references to Fulton anywhere."

**After:** Two words into Total Recall: "fulton house." It found a single reference in a care-coordination session from the previous month, revealing the Fulton House was a family member's bed-and-breakfast, including the booking email, management platform, and credential storage location. This context bootstrapped an entirely new project when the developer disclosed a family member had passed away and they needed to take over administration.

**Pattern:** Cross-session continuity / Knowledge recovery
**Audience:** Anyone using AI across life domains (not just code)
**Source:** inv-002 (Batch 1)

---

## 8. "I Thought We Discussed Pricing. Did We Ever Actually Decide?"

**Before:** A developer was planning a product launch and believed pricing had been decided in a prior session. They did not want to re-debate it.

**After:** Total Recall ran 8 queries across 180 days of conversation history. It found the full evolution of pricing thinking: from "Free. The whole thing." at initial launch, to a specific user offering $10 for a license, to discussions about paid tiers. But the definitive finding was: no final pricing decision was ever made. What the developer remembered as a "decision" was actually an ongoing discussion. They could now make the call with full historical context instead of re-deriving it from scratch.

**Pattern:** Decision archaeology / Negative proof
**Audience:** Solo dev, founder, product manager
**Source:** B4-004 (Batch 4)

---

## 9. "I Totally Lost Track of That Schema Work"

**Before:** A developer said "we had been working on updating the schema so that this page could show projects with worktrees rolled up. I thought that work was done but have totally lost it."

**After:** Total Recall found the work was completed the previous day, in a different worktree, using a different AI tool (Codex vs Claude Code). Two atomic commits with exact hashes were identified, on a specific branch that had never been merged. The developer reviewed the diffs and merged immediately.

**Pattern:** Cross-session / Cross-tool continuity
**Audience:** Multi-machine user, developer using multiple AI tools
**Source:** batch5-001 (Batch 5)

---

## 10. "You Set This Server Up. I Have No Idea What the IP Is."

**Before:** A developer needed to deploy to a cloud server that an AI session had provisioned days earlier. The deployment runbook had an old IP address. The developer could not remember the correct one.

**After:** Total Recall found the correct server IP (different from the runbook), the SSH key path, and the provisioning session that created the droplet. It also corrected a discrepancy between the runbook and reality. Deployment proceeded with the correct credentials.

**Pattern:** Implementation reference / Infrastructure recall
**Audience:** Solo dev managing cloud infrastructure
**Source:** B4-008 / B4-009 (Batch 4)

---

## 11. "Validate All Our P1 Tasks and Close What's Already Done"

**Before:** A developer had 20+ open P1 priority tasks. Some might have been completed in prior sessions but never marked done. Manually checking each would take hours.

**After:** Two parallel Total Recall agents triaged the full task list, cross-referencing each against conversation history and git logs. Result: all recent P1s were genuinely open (no free closes), but the audit surfaced a quick-fix bug that was immediately implemented. The systematic sweep gave confidence that the task backlog was accurate.

**Pattern:** Batch audit / Systematic verification
**Audience:** Solo dev, team lead managing backlogs
**Source:** B4-015 (Batch 4)

---

## 12. "Who Created This Git Hook and Why Does It Block docs/?"

**Before:** A pre-commit hook was blocking commits to the docs/ directory. The hook was in .git/hooks/ (untracked by git, invisible to git log). No one could explain why docs/ was blocked.

**After:** Total Recall found the original session (~Feb 16, 2026) that created the hook. The reasoning: at the time, there was a plan to push the repo to GitHub, so docs/ was blocked preemptively as a privacy measure. Since the GitHub push never happened, the block was now unnecessary.

**Pattern:** Debugging history / Decision archaeology
**Audience:** Solo dev, anyone inheriting AI-created configuration
**Source:** inv-005 (Batch 1)

---

## 13. "Was This Setting Intentional or a Mistake?"

**Before:** A developer found `push_to_canonical=false` in a worktree initialization script. They could not tell if this was an intentional decision or a bug introduced by a prior AI session.

**After:** Total Recall found the explicit decision from March 21 with full reasoning: `push_landing=false` means landing branches are local-only; `push_to_canonical=false` means AI should not push directly to main. Both settings were confirmed correct and intentional.

**Pattern:** Decision recall / Configuration provenance
**Audience:** Solo dev, team reviewing AI-authored configuration
**Source:** B4-006 (Batch 4)

---

## 14. "Has the Code Review Already Been Done?"

**Before:** A developer was about to run an automated code review loop on a feature branch. But another AI session on a different worktree might have already completed the review.

**After:** Total Recall confirmed a genuine 2-iteration review loop had already been completed the same day on a different worktree. The result was merge-ready with one concern split into a separate task. The developer avoided duplicating the review and proceeded to merge the already-reviewed code.

**Pattern:** Negative proof / Duplicate work prevention
**Audience:** Solo dev with multiple worktrees, team with parallel AI agents
**Source:** batch5-004 (Batch 5)

---

## 15. "I Knew We Discussed This Cloud Architecture Vision Somewhere"

**Before:** A developer and their AI had just articulated a vision for expanding a cloud backend to serve multiple AI CLI tools. The AI said "that vision isn't captured anywhere in docs or tasks, it was discussed but not written down."

**After:** Total Recall found the original conversation where the developer had explicitly articulated the hosted private instance vision, including self-hosted or cloud-hosted PostgreSQL, workgroup features, and multi-user accounts. The verbatim user quote was recovered and used to anchor the architectural direction going forward.

**Pattern:** Knowledge search / Undocumented vision recovery
**Audience:** Solo dev, architect, founder
**Source:** batch5-002 (Batch 5)

---

## Pattern Distribution

| Pattern | Cases | Example # |
|---------|-------|-----------|
| Decision recall / archaeology | 6 | 1, 4, 8, 12, 13 |
| Cross-session continuity | 5 | 2, 7, 9, 14, 15 |
| Implementation reference | 3 | 5, 10, 6 |
| Incident forensics | 2 | 6, 12 |
| Negative proof | 3 | 8, 11, 14 |
| Precision recall | 1 | 3 |
| Batch audit | 1 | 11 |

## Audience Segment Mapping

| Segment | Cases that resonate |
|---------|-------------------|
| **Solo developer** | All 15 (primary audience) |
| **Multi-machine / multi-tool user** | 9, 14, 6 |
| **Team lead / manager** | 4, 6, 11, 14 |
| **Founder / product owner** | 8, 15 |
| **Non-code / life admin user** | 3, 7 |
| **Infrastructure / DevOps** | 10, 6 |

## Usage Notes for Marketing

1. **Lead with the stakes.** Cases 1, 3, and 7 have the highest emotional resonance because the consequences of not having Total Recall are concrete and costly.

2. **The "I thought we did X" opening is universal.** Cases 2, 4, 5, 8, 9, 13, 14, and 15 all start with a developer's vague memory. This is the core pain point: human memory degrades, AI sessions are ephemeral, and the gap between them is where work gets lost.

3. **Negative proofs are counterintuitive value.** Cases 8, 11, and 14 deliver value by confirming absence. "We never decided" and "it hasn't been done" are as actionable as "here's what happened." This is a differentiating message: Total Recall gives you confidence in what you know AND what you do not.

4. **Cross-tool provenance is a growth story.** Cases 6, 9, and 14 involve multiple AI tools (Claude Code + Codex). As developers use more AI tools, the need for unified conversation history grows. This is a strong pitch for the cloud sync product.

5. **Privacy note:** All cases have been scrubbed of specific product names, client names, and identifiable details. Project descriptions are generic ("a macOS developer tool," "a personal administration project"). Financial figures in case 1 are from the developer's own business, not a client's.
