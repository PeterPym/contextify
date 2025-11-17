# Documentation Audit - Questions for Review

**Date:** 2025-11-17
**Auditor:** Claude

Questions that block progress on specific documents. Please review and answer so I can complete the audit.

---

## Questions

### Q1: build/docs/architecture/data-flow.md - Outdated Information

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
   - Claims about "transcript inventory gap" may be outdated

**Questions:**
- Should data-flow.md be updated with correct line numbers and batch sizes?
- Is the "transcript inventory gap" still accurate, or was it fixed when SidecarMetadataStore was removed?
- Should we verify the entire 1183-line document against current code?
- Or should this be marked as "historical" and moved to archive, replaced with new data pipeline doc?

**Impact:** HIGH - This is referenced as "definitive reference" but contains multiple factual errors that will mislead developers.
