# Phase 1: Discovery & Documentation - Summary

**Date:** 2025-10-24
**Status:** ✅ COMPLETE
**Duration:** ~1 hour

---

## Deliverables

### 1. Claude Code Tool Inventory
**File:** `claude-code-tool-inventory.md`

**Key Findings:**
- **15 unique tool types** identified
- **7,601 total tool calls** analyzed from Contextify project transcripts
- **Top 3 tools** account for 80.7% of usage:
  - Bash: 44.1% (3,305 calls)
  - Edit: 19.7% (1,474 calls)
  - Read: 16.9% (1,264 calls)

**Coverage:** Documented input/output structure, parameters, and conversion strategy for all tools.

---

### 2. Codex CLI Tool Inventory
**File:** `codex-tool-inventory.md`

**Key Findings:**
- **2 unique function types** identified (limited sample)
- **35 total function calls** analyzed from October 2025 sessions
- **Dominant function:**
  - shell: 88.6% (31 calls)
  - update_plan: 11.4% (4 calls)

**Note:** Sample size is much smaller than Claude Code. Codex may have additional functions not captured in this sample.

**Coverage:** Detailed `shell` function specification with argument/output parsing rules.

---

### 3. Tool Compatibility Matrix
**File:** `tool-compatibility-matrix.md`

**Key Findings:**

| Tier | Strategy | Tools/Functions | Coverage |
|------|----------|-----------------|----------|
| **Tier 1** | Direct conversion (non-lossy) | Bash ↔ shell | CC: 44%, Codex: 89% |
| **Tier 2** | Lossy text summary | Edit, Read, Grep, Write, Glob, BashOutput | CC: 47% |
| **Tier 3** | Skip entirely | TodoWrite, WebSearch, update_plan, etc. | CC: 9%, Codex: 11% |

**Total Coverage:** Tier 1 + Tier 2 capture **90.9%** of Claude Code tool usage context.

**Specifications:** Detailed conversion algorithms for:
- Bash ↔ shell with command wrapping/unwrapping
- Edit, Read, Grep, Write, Glob summarization templates
- Timestamp management and call ID mapping
- Error handling and edge cases

---

## Key Insights

### 1. Bash/shell Conversion is Critical
- Accounts for **44%** of Claude Code calls and **89%** of Codex calls
- Contains high-value context (commands tried, outputs, errors)
- **Must-have** for Phase 2 implementation

### 2. File Operations Are Claude Code-Specific
- Edit, Read, Write, Grep, Glob have **no Codex equivalents**
- Represent **47%** of Claude Code usage
- Lossy conversion via text summaries is acceptable (preserves "what happened")

### 3. Codex Has Fewer Tools
- Only 2 function types identified vs Claude Code's 15 tools
- Possible explanations:
  - Codex delegates more to shell commands
  - Limited sample size
  - Different design philosophy (fewer specialized tools)

### 4. Planning Tools Should Be Skipped
- TodoWrite (Claude Code) and update_plan (Codex) are UI state
- No lasting code context
- Safe to omit during conversion

---

## Implementation Roadmap

### Phase 2a: Tier 1 Implementation (Estimated: 4-6 hours)
**Goal:** Direct Bash ↔ shell conversion

**Tasks:**
1. Implement command parsing/wrapping functions
2. Implement call ID mapping (toolu_ ↔ call_)
3. Implement exit code mapping (is_error ↔ exit_code)
4. Handle workdir inference (Claude Code → Codex)
5. Create unit tests for edge cases:
   - Commands with quotes, pipes, newlines
   - Large outputs (>100KB truncation)
   - Failed commands (non-zero exit)
   - Orphan tool results/uses

**Success Criteria:**
- Round-trip conversion preserves Bash/shell calls
- All test cases pass
- Real transcript with 50+ Bash calls converts cleanly

---

### Phase 2b: Tier 2 Implementation (Estimated: 3-4 hours)
**Goal:** Lossy summarization for file operations

**Tasks:**
1. Define summarization templates (already in matrix)
2. Implement template rendering functions
3. Extract parameters from tool inputs
4. Inject summaries as assistant text messages
5. Create unit tests for each tool type

**Success Criteria:**
- Summaries are human-readable and informative
- Conversion maintains conversation coherence
- Edge cases handled (missing fields, errors)

---

### Phase 2c: Testing & Polish (Estimated: 3-4 hours)
**Goal:** Validate with real transcripts

**Tasks:**
1. Integration tests with real Contextify transcripts
2. Round-trip validation (CC → Codex → CC)
3. Resume converted session and test context awareness
4. Add conversion report output
5. Document known limitations

**Success Criteria:**
- Real transcripts convert without errors
- Resumed sessions can reference tool execution history
- Conversion report shows accurate statistics
- Documentation updated

---

## Statistics

### Conversion Coverage Projection

**Claude Code Tools:**
- Tier 1 (direct): 44.1% of calls
- Tier 2 (lossy): 46.8% of calls
- Tier 3 (skip): 9.1% of calls
- **Total preserved context: 90.9%**

**Codex Functions:**
- Tier 1 (direct): 88.6% of calls
- Tier 3 (skip): 11.4% of calls
- **Total preserved context: 88.6%**

### Time Estimate

- Phase 1 (Discovery): ✅ 1 hour (COMPLETE)
- Phase 2 (Implementation): 🔄 10-14 hours (PENDING)
  - 2a (Tier 1): 4-6 hours
  - 2b (Tier 2): 3-4 hours
  - 2c (Testing): 3-4 hours
- Phase 3-6 (Error Handling, Testing, Docs): 🔄 5-8 hours (PENDING)

**Total Project Estimate:** 16-23 hours (revised from original 15-22)

---

## Open Questions Resolved

### Q1: Are shell/bash commands worth preserving?
**A:** ✅ YES - They account for 44% of Claude Code and 89% of Codex usage. High value.

### Q2: Can we convert file operations (Edit, Read, etc.)?
**A:** ✅ YES - Via lossy text summaries. Covers 47% of Claude Code usage.

### Q3: What's the minimum viable conversion?
**A:** Tier 1 (Bash ↔ shell) alone captures 44% of Claude Code context. This is the MVP.

### Q4: Should we preserve planning tools (TodoWrite, update_plan)?
**A:** ✅ NO - They're UI state with no code context. Safe to skip.

---

## New Questions for Phase 2

### Q1: Workdir Inference Strategy
When converting Claude Code → Codex, how do we infer `workdir`?
- **Option A:** Use project root from session context
- **Option B:** Parse from relative paths in recent file operations
- **Option C:** Default to user home directory

**Recommendation:** Option A (project root) with fallback to CWD from session metadata.

### Q2: Call ID Collision Handling
What if source transcript has both `call_abc` and `toolu_abc` that would map to same ID?

**Recommendation:** Add collision detection and append suffix (`call_abc_2`).

### Q3: Timestamp Precision
Source timestamps may have varying precision (ms, μs). How do we normalize?

**Recommendation:** Round to milliseconds; use 1ms increments for monotonicity.

### Q4: Large Output Truncation
Should we truncate head+tail or just head for large outputs?

**Recommendation:** Head + tail (first 50KB + last 50KB) preserves both error location and final result.

---

## Files Created

1. `build/notes/research/rag/claude-code-tool-inventory.md` (329 lines)
2. `build/notes/research/rag/codex-tool-inventory.md` (343 lines)
3. `build/notes/research/rag/tool-compatibility-matrix.md` (567 lines)
4. `build/notes/research/rag/phase-1-summary.md` (this file)

**Total Documentation:** ~1,300 lines

---

## Next Steps

**Immediate (Phase 2a):**
1. Review deliverables with user
2. Validate conversion strategy
3. Begin Tier 1 (Bash ↔ shell) implementation in `scripts/transcripts/convert_transcript.py`

**User Decision Points:**
- Approve tiered conversion strategy?
- Approve lossy summarization templates for Tier 2?
- Approve skipping Tier 3 tools?
- Should we proceed with Phase 2a implementation?

---

## References

- Implementation Plan: `/tmp/tool-call-conversion-implementation-plan.md`
- Context Doc: `/tmp/tool-call-conversion-context.md`
- Transcript Format: `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
- Current Converter: `scripts/transcripts/convert_transcript.py`
