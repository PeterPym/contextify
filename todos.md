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

### Automated QA Test Suite (MVP - Local Execution)

**Issue:** Need automated regression testing for core Contextify workflows before releases

**Context:**
- Manual testing is time-consuming and error-prone
- Critical flows (startup, project switching, transcript discovery, real-time updates) need validation
- Pre-release sanity checks currently done ad-hoc

**MVP Scope:**
- **Local execution only** - Sequential bash scripts on development machine
- **Real integrations** - Uses actual Codex/Claude CLIs, not fixtures
- **6 core test cases** - Validates end-to-end pipeline (FSEvents → Database → Timeline → UI)
- **Fast feedback** - Complete suite in <10 minutes with clear pass/fail

**Test Coverage:**
1. **QA-01:** App launch and startup orchestration
2. **QA-02:** Project switching with AppleScript automation
3. **QA-03:** Codex transcript discovery (canonical template)
4. **QA-04:** Claude Code transcript discovery
5. **QA-05:** Real-time transcript updates (incremental hoover)
6. **QA-06:** Watcher health check and recovery

**Implementation Approach:**
- Bash scripts leveraging existing `scripts/logging/` toolkit
- Log pattern matching with `wait_for_log_pattern` helper (no blind sleeps)
- Direct SQLite queries with timeout for WAL lock handling
- Sequential execution via `run-all-tests.sh` orchestrator

**Expected Outcomes:**
- Pre-release validation in <10 minutes
- Catch regressions in FSEvents, database ingestion, timeline refresh
- Clear diagnostics when tests fail (log patterns, DB state, troubleshooting steps)
- Foundation for future CI/CD integration (v2)

**Implementation Documents:**
- **Full methodology (v2 - MVP):** `build/notes/reference/automated-qa-methodology-v2.md`
- **Original analysis (v1):** `/tmp/contextify-automated-qa-methodology.md`
- **Review feedback:** `/private/tmp/got-it-that-helps.md`

**Implementation Checklist:**
1. Create `scripts/qa/` directory structure
2. Implement `lib/common.sh` with `wait_for_log_pattern`, `db_query` with timeout
3. Implement `lib/assertions.sh` (exact count validation only)
4. Implement `run-all-tests.sh` sequential orchestrator
5. Implement QA-03 first (canonical example)
6. Pattern-match QA-01, QA-02, QA-04, QA-05, QA-06 from QA-03
7. Test full suite locally
8. Document usage

**Effort:** Medium (8-12 hours total)
- Helper libs: 2 hours
- QA-03 implementation: 3 hours
- Other test cases: 3-4 hours
- Testing and refinement: 2-3 hours

**Deferred to v2 Professional QA:**
- CI/CD GitHub Actions integration
- Fixture-based tests (no live API calls)
- Database migration testing
- Performance benchmarks with timing assertions
- Headless controls (no AppleScript dependency)

**Priority:** P1 (implement before next major feature work)

**Status:** Planning complete, ready for implementation

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
