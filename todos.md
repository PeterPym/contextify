# Technical Debt & Future Improvements

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
