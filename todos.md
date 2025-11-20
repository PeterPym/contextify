# Technical Debt & Future Improvements

## P1 (High Priority - Post-Release)

### User Timeline Summarization Improvement

**Issue:** User message timeline summaries lack the quality and disposition accuracy of assistant-side summaries

**Context:**
- Assistant-side timeline summarization was significantly improved (feature/timeline-summarization-disposition-fix)
- Added explicit disposition guidance, verb-tense rules, and postProcess validation
- User side deserves similar treatment for consistency and quality

**Current Problems:**
1. User prompt is basic, lacks explicit disposition definitions
2. Occasional validation mismatches (now gracefully handled, but prompt should guide better)
3. Inconsistent verb choice for user summaries
4. No parity between user and assistant prompt quality

**Impact:**
- User summaries less polished than assistant summaries
- Timeline clarity could be better for project retrospectives
- Occasional confusion between directives, questions, and reports

**Solution Approach:**
Three-layer improvement (mirrors assistant-side fix):
1. **Strengthen user prompt** - Add explicit disposition taxonomy with examples
2. **Trust classifyUserIntent** - Override LLM when classifier disagrees
3. **Optional lexical seatbelts** (P2) - Minimal rules only if monitoring shows need

**Expected Outcomes:**
- ≥90% user disposition accuracy (parity with assistant)
- Consistent verb patterns matching disposition
- <2% validation mismatches (improved from ~5-10%)
- Better symmetry between user and assistant timeline quality

**Implementation Documents:**
- **Problem analysis:** `build/docs/planning/user-timeline-summarization-improvement.md`
- **Step-by-step guide:** `build/docs/planning/user-timeline-implementation-guide.md`
- **Critical checks:** `build/docs/planning/user-timeline-implementation-checklist.md`

**Effort:** Medium (3-6 hours total)
- Prompt rewriting: 1-2 hours
- postProcess integration: 1 hour
- Manual validation: 1-2 hours
- Documentation and commit: 30 min

**Related:**
- Assistant fix commits: b88794e, 8007f04, 0d68c05
- User validation fix: 29dcac4
- Colleague feedback: `/private/tmp/yes-i-ve-got-colleague-c-user-facing-prompt-rework.md`

**Priority:** P1 (do after release, before next major feature)

**Status:** Planning complete, implementation ready

---

## P3 (Low Priority - Nice to Have)

### Timeline Fix Test Infrastructure

**Test Case Deduplication**
- **Issue:** `TimelineFixValidationTests.swift` and `scripts/validate-timeline-fix.swift` both hard-code similar sets of 13 test cases
- **Risk:** Will drift over time as one gets updated and the other is forgotten
- **Solution:** Extract shared cases into a single source of truth
  - Option 1: `SharedTimelineFixCases.json` in test resources
  - Option 2: Shared Swift struct in `ScriptsSupport` module
  - Option 3: Add comment in script pointing to XCTest file as authoritative set (minimal fix)
- **Effort:** Low-Medium (depends on chosen approach)
- **Priority:** P3 (maintenance ergonomics, not correctness)
- **Related:** `Contextify/ContextifyTests/TimelineFixValidationTests.swift`, `scripts/validate-timeline-fix.swift`
