# Documentation Audit - Questions for Review

**Date:** 2025-11-17
**Auditor:** Claude

Questions that block progress on specific documents. Please review and answer so I can complete the audit.

---

## Questions

### ✅ Q1: build/docs/architecture/data-flow.md - Outdated Information (RESOLVED)

**Document:** data-flow.md (last updated 2025-10-22, ~1 month old)

**Issues Found:**
1. **Line numbers are all incorrect** (off by hundreds/thousands):
   - Claims `HooverEngine.hooverTranscript()` at lines 2900-3100, actually at line 263 (file is only 898 lines)
   - Claims `TranscriptWatcher.watch()` at lines 2650-2730, actually at line 61 (file is only 307 lines)
   - Claims `ConversationMonitor.startMonitoring()` at lines 130-213, actually at line 428

2. **Batch size is wrong**:
   - Document claims "100 lines at a time" (lines 56, 286)
   - Actual code shows `batchLines: Int = 1000` (HooverEngine.swift:11)

3. **References non-existent file**:
   - Document extensively discusses `SidecarMetadataStore` as in-memory cache (lines 483, 486, 966, 1046, 1117)
   - File `SidecarMetadataStore.swift` does not exist in codebase
   - Claims about "transcripts gap" may be outdated

**Resolution:** ARCHIVED (2025-11-17)

After systematic line-by-line verification, determined document is not salvageable:
- Architecture fundamentally changed since Oct 22 (StartupCoordinator commits Nov 12-17)
- Core functions referenced don't exist (`discoverNewTranscripts`, `watchForDebouncedTranscriptUpdates`)
- Line numbers off by thousands (not hundreds)
- References non-existent components (SidecarMetadataStore.swift)
- Described workflows no longer match current implementation

**Action Taken:**
- Moved to `build/docs/archive/historical/data-flow-2025-10-22.md`
- Replacement doc proposed: See `PROPOSED-DOCUMENTATION.md` #1 (Complete Data Pipeline Architecture)

**Impact:** Eliminated misleading documentation; replacement doc will be based on current architecture (StartupCoordinator, current ConversationMonitor, actual HooverEngine).
