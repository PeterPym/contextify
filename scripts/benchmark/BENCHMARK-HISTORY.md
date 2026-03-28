# Total Recall: Skill & Benchmark History

How we arrived at the current SKILL.md and evaluation system.

## Timeline

### Phase 0: SKILL.md Creation (Jan-Feb 2026)

The Total Recall skill began as documentation for Claude Code agents to search the Contextify conversation database. Early work was iterative:

| Date | Commit | Change |
|------|--------|--------|
| 2026-01-26 | `38a2cf95` | First hardened version: error envelope corrections, query guidance |
| 2026-02-19 | `68d6c063` | Switch from `total-recall` to `contextify` as primary CLI command |
| 2026-02-21 | `1639c7b5` | Document undocumented CLI features (--full-content, --snippet-tokens) |

At this point, SKILL.md existed but had no automated quality measurement. Changes were evaluated by manual testing.

### Phase 1: Benchmark Harness (2026-03-26, ct-695)

**Problem**: No way to measure whether SKILL.md changes improved or regressed search quality.

**Solution**: Built the benchmark harness with 14 gold queries derived from real user sessions. Each query has:
- A natural-language question (what a user would ask)
- Search terms (what the CLI should search for)
- A content fingerprint (text that must appear in results to count as "found")
- An efficiency budget (max acceptable searches)

The frozen DB snapshot (1.8GB) captures a real database with ~months of conversation history across multiple projects.

| Date | Commit | Change |
|------|--------|--------|
| 2026-03-26 | `36bff509` | Initial benchmark harness (ct-695): evaluate.sh, gold-queries.json, snapshot |
| 2026-03-26 | `1d441909` | Review feedback: BH-02 through BH-04 fixes |
| 2026-03-26 | `d1b29464` | Merge ct-695-benchmark-harness |
| 2026-03-26 | `cc215933` | Follow-up fixes: ct-709, ct-710, ct-711 |

**Design decisions**:
- **Why 14 queries?** Selected to cover 5 categories: decision-archaeology (5), session-opener (3), cross-session-continuity (2), debugging (1), implementation-reference (2), plus 1 hard pricing query. Each verified against the frozen snapshot.
- **Why content fingerprints?** Exact substring matching is deterministic. The evaluator checks whether specific text from the database appears in search results. No judgment calls.
- **Why a frozen snapshot?** Reproducibility. The same DB produces the same results every time.

**CLI baseline**: 100.0 (14/14 PASS). The CLI + gold search terms always find the right content.

### Phase 2: P0 Proposals (2026-03-26, ct-708)

A 38-invocation usage analysis (ct-671) identified 6 improvements. These were CLI and SKILL.md changes, not benchmark changes.

| ID | Change | Impact |
|----|--------|--------|
| F-01 | Shim TTY gating | Suppressed "Multiple installs" noise in non-interactive use |
| F-02 | FTS5 hyphen preprocessing | `cli-ai-setup` no longer causes "no such column" errors |
| F-03 | --project name-based lookup | `--project contextify` works (not just paths) |
| F-04 | Default snippet-tokens 10 -> 50 | Matches what 29/33 users manually overrode to |
| F-05 | Better FTS5 error messages | Actionable hints instead of raw SQLite errors |
| F-07 | Zero-result escalation protocol | 5-step mandatory escalation in SKILL.md |
| F-08 | Pre-search hyphen checklist | Rewrite table for hyphens, underscores, dots |

**Key commits**: `36f273e7` (F-01), `45a9e302` (F-02+F-05), `d1a30564` (F-03), `012099ce` (F-07+F-08)

CLI benchmark remained 100.0 throughout. But a crucial observation emerged: **CLI-mode benchmarks cannot validate SKILL.md changes** (F-07, F-08) because those change AI behavior, not CLI search behavior. This led directly to Phase 3.

### Phase 3: AutoResearch Ratchet Loop (2026-03-27, ct-724)

**Goal**: Measure and improve how well an AI agent uses SKILL.md to answer questions. The skill-mode benchmark runs headless Claude Code against each gold query's natural-language question.

**Protocol** (following Karpathy's AutoResearch pattern):
- Mutable artifacts: SKILL.md, run-skill-query.sh, CLI code
- Immutable evaluator: evaluate.sh scoring logic, gold-queries.json, frozen DB
- Rule: Keep changes that improve the score. Revert regressions. Log everything.

**Initial skill-mode baseline: 10.6/100** (5/14 PASS)

#### Ratchet iterations

| Iter | Change | Score | Kept? |
|------|--------|-------|-------|
| 1 | Prompt: --days 365, --snippet-tokens 50, retry guidance | 15.8 | Yes |
| 2 | SKILL.md: "Step 0: Extract distinctive terms" | 11.6 | Reverted |
| 3 | Prompt: verbatim quote emphasis | 11.9 | Reverted |
| 4 | Prompt: --full-content + quoting | 11.9 | Reverted |
| 5 | Prompt: structured search protocol | 31.3 | Reverted |

**The ratchet loop produced zero lasting SKILL.md improvements.** Only iteration 1 (prompt-level changes to the runner script) stuck.

#### The measurement error discovery

Manual debugging of gq-02 revealed the real problem. The AI produced a detailed, correct answer about Perch Innovations and Delaware franchise tax. But the evaluator checked for the exact substring `"A Delaware C-corp (Perch Innovations Inc) has its own"`. The AI naturally synthesized the information instead of quoting verbatim.

**The evaluator was punishing correct answers because the AI paraphrases.**

#### Evaluator evolution

| Fix | Score delta | What changed |
|-----|-------------|--------------|
| Word-level matching | 15.8 -> 32.4 | Extract 4+ char words from fingerprint, check 80%+ appear in response |
| Infra resilience | - | Timeouts score as failures instead of aborting |
| Parallel execution | - | 15 min -> 3 min per run (4 workers) |
| Stem-aware matching | 32.4 -> 35.0 | "hats" matches "hat", "planned" matches "planning" |
| 70% threshold | 35.0 -> 41.7 | Lowered from 80% to 70% word match required |

#### The SKILL.md rewrite attempt

A ChatGPT review suggested cutting SKILL.md by 30-40%. A major rewrite (579 -> 225 lines) scored comparably (40.2 vs 45.8) but deleted critical features: git-anchored search, FTS5 behavior reference, JSON schemas, worktree expansion, counting/audit guidance, partial results handling.

**Reverted.** Replaced with 3 surgical edits (+17 lines net):
1. Fixed canonical loop defaults (--days 365 instead of --days 30)
2. Added entity-first priority rule
3. Added snippet-vs-context decision gate

**Lesson**: Benchmark optimization and product completeness are different goals. A shorter skill can score the same while losing features real users need.

### Phase 4: Benchmark Integrity (2026-03-27, ct-730/ct-731)

**The second measurement crisis.** After merging ct-708 and beginning the ratchet loop, we discovered `run-skill-query.sh` was feeding Claude Code a hardcoded 10-line prompt instead of the actual 595-line SKILL.md. Every skill-mode score was bogus.

| Date | Commit | Fix |
|------|--------|-----|
| 2026-03-27 | `adb60f5d` | ct-731: SKILL.md emits `skill:<hash>` in output header |
| 2026-03-27 | `e8b71a90` | ct-730: Evaluator verifies hash match in agent output |
| 2026-03-27 | `e0f6affd` | ct-730: Behavioral verification (--days 365, --snippet-tokens 100, --db-path) from tool calls |
| 2026-03-27 | `69f1a8b3` | Annotate all prior skill scores as INVALID in results.tsv |

**First verified baseline: 37.0** (11/14 found, 14/14 behavioral compliance, skill:72771ddf)

**A/B comparison** (both verified):
- Old SKILL.md (pre-ct-708, skill:760873c0): **23.1** (8/14 found)
- New SKILL.md (current, skill:72771ddf): **37.0** (11/14 found)

The 60% improvement came from human-directed work (CLI fixes + 3 surgical SKILL.md edits), not from the automated ratchet loop.

### Phase 5: Evaluator Calibration & Freeze (2026-03-27, ct-729)

**Goal**: Validate the 70% word-match threshold and freeze the evaluator.

**Method**: Hand-labeled 36 pairs:
- 20 true positives (AI responses that genuinely found content, from exact quotes to heavy paraphrases)
- 11 true negatives (wrong topic, same-topic-different-context, explicit "not found")
- 5 edge cases (heavy paraphrase, stemmed forms, names missing, wrong-project-same-tech)

**Threshold sweep** (F1 on labeled data):

| Threshold | Precision | Recall | F1 |
|-----------|-----------|--------|------|
| 0.50 | 0.74 | 1.00 | 0.85 |
| 0.60 | 0.77 | 1.00 | 0.87 |
| **0.70** | **0.86** | **0.90** | **0.878** |
| 0.80 | 0.89 | 0.85 | 0.87 |

0.70 confirmed as optimal.

**Two targeted improvements** from ChatGPT review:
1. **Negation-aware matching**: When response contains "not found", "couldn't find", etc., threshold increases to 0.95. Catches false positives from topic-adjacent "I didn't find it" responses. (F1: 0.878 -> 0.900)
2. **Numeric token inclusion**: Issue IDs like "287" (>= 3 digits) qualify as fingerprint words with exact-match semantics. Prevents future false positives on numeric discriminators.

**Known limitations** (2 irreducible false positives):
- gq-07 fingerprint (`SENTRY_ENVIRONMENT=production`): Only 3 generic words. Any monitoring + production discussion matches.
- gq-10 fingerprint (`ct-287-cloud-worktree-grouping`): All non-numeric words are generic domain terms.

Root cause: Word-level matching cannot distinguish "I found X" from "X was mentioned but not found." Fixing requires semantic analysis, out of scope for a bash evaluator.

**Evaluator frozen** at commit `e669a48b`. Changes require re-running `calibrate-fingerprint.py` with updated labeled pairs.

---

## Key Lessons

### 1. The evaluator is as important as the artifact
The biggest score gains came from fixing measurement errors (word matching, stem matching), not from improving SKILL.md. If the eval punishes correct answers, no amount of artifact improvement helps.

### 2. Verify the test harness tests what you think it tests
The bogus-benchmark discovery (ct-730) showed that `run-skill-query.sh` wasn't loading SKILL.md at all. We ran 5 ratchet iterations, multiple review rounds, and recorded scores before catching this. Hash verification and behavioral compliance checks now prevent recurrence.

### 3. Automated ratchet loops have limits for prompt engineering
Iterations 2-5 all tweaked the prompt or SKILL.md with marginal or negative results. The high-leverage changes were structural (CLI improvements, evaluator fixes). The ratchet pattern works well for measurable, mechanistic changes but less well for prompt wording where the search space is vast and feedback is noisy.

### 4. Don't optimize benchmarks at the expense of product completeness
A major SKILL.md rewrite scored comparably while deleting features real users need. The benchmark measures 14 specific queries, not the full surface area of user needs.

### 5. Stochastic evaluation requires care
The AI constructs different queries each run. A single measurement has high variance. The verified baseline (37.0) is a point estimate, not a precise measurement. Median-of-3 scoring (ct-727, not yet implemented) would improve confidence.

---

## Current State (2026-03-27)

| Component | Status | Score |
|-----------|--------|-------|
| CLI search quality | Stable | 100.0 (14/14) |
| SKILL.md (skill:72771ddf) | Stable | 37.0 verified (11/14) |
| Pre-ct-708 SKILL.md | Archived | 23.1 verified (8/14) |
| Evaluator | **Frozen** (ct-729) | F1=0.900 |
| Gold queries | 14 verified | 6 high-risk fingerprints |

### Files

| File | Purpose |
|------|---------|
| `scripts/benchmark/evaluate.sh` | Frozen evaluator (scoring logic) |
| `scripts/benchmark/gold-queries.json` | 14 gold queries with fingerprints |
| `scripts/benchmark/results.tsv` | Score history (annotated) |
| `scripts/benchmark/calibrate-fingerprint.py` | Calibration harness (36 labeled pairs) |
| `scripts/benchmark/run-skill-query.sh` | Skill runner (headless Claude Code) |
| `scripts/benchmark/ratchet.sh` | AutoResearch ratchet loop |
| `scripts/benchmark/prepare-snapshot.sh` | Snapshot creation |
| `scripts/benchmark/snapshot-manifest.json` | Snapshot metadata + hash |
| `contextify-query/user-skill/total-recall/SKILL.md` | The skill (602 lines) |

### Open work

| Issue | Priority | Description |
|-------|----------|-------------|
| ct-727 | P2 | Median-of-3 scoring to reduce stochastic variance |
| ct-728 | P1 | Per-query trace persistence for post-mortem diagnosis |
| ct-732 | P2 | Skill output format polish |
| ct-733 | P2 | Symlink SKILL.md for dev workflow |
