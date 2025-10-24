# Contextify: Remaining Work for Cross-CLI Transcript Resumption Launch

## Current State Summary

**What's Complete:**
- ✅ SQL backend with multi-provider support (Claude Code + Codex CLI parsers)
- ✅ Unified timeline display with provider-specific icons
- ✅ Multi-project discovery and auto-ingestion
- ✅ Standalone transcript converter script (`convert_transcript.py`) - 424 lines
- ✅ Comprehensive format documentation (6 docs, 1,151 lines)
- ✅ Real-time file watching and monitoring
- ✅ Apple Intelligence integration for summaries
- ✅ Timeline cache with content-based invalidation

**What's Missing for Launch:**
- ❌ UI integration for converter (no menu actions/buttons)
- ❌ Tool call preservation (Phase 2)
- ❌ Automated test suite
- ❌ Preview/validation UI

---

## Phase 1: Merge Converter to Main (1 day)

### Goal
Get the converter foundation into main branch so users can try it from CLI.

### Tasks

**1.1 Merge feature/transcript-converter branch**
- Review converter script one more time
- Check documentation is complete
- Merge PR to main
- **Deliverable:** Converter available in `scripts/` on main

**1.2 Update main README**
- Add "Transcript Conversion" section
- Include quick start example
- Link to converter docs
- **Deliverable:** Users know converter exists and how to use it

**1.3 Test converter end-to-end**
- Convert real Claude Code session → Codex
- Resume in Codex CLI, verify continuity
- Convert Codex session → Claude Code
- Resume in Claude Code, verify continuity
- **Deliverable:** Verified working for basic messages

**Time estimate:** 1 day
**Priority:** HIGH (enables manual workflow)
**Blocker:** None

---

## Phase 2: UI Integration (3-4 days)

### Goal
Let users convert transcripts from Contextify UI without command line.

### Tasks

**2.1 Add context menu actions to TranscriptInventoryView**
- Right-click on transcript row → "Export to Codex CLI" or "Export to Claude Code"
- Show menu item based on current provider
- Disable if same provider (no conversion needed)
- **File:** `TranscriptInventoryView.swift`
- **Time:** 0.5 day

**2.2 Create export file picker**
- Use `NSOpenPanel` for save dialog
- Auto-generate proper filename:
  - Codex: `rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl`
  - Claude Code: `session-<uuid>.jsonl`
- Auto-suggest proper directory:
  - Codex: `~/.codex/sessions/YYYY/MM/DD/`
  - Claude Code: `~/.claude/projects/<project-path>/`
- **File:** New `TranscriptExportView.swift` or inline
- **Time:** 0.5 day

**2.3 Implement converter in Swift**
- Rewrite converter logic in Swift (~300-400 lines based on Python reference)
- Create shared `TranscriptConverter.swift` module
- Benefits: No Python dependency, faster, native error handling, type safety
- Structure:
  ```swift
  enum TranscriptFormat { case claudeCode, codexCLI }

  struct TranscriptConverter {
      static func convert(
          from: TranscriptFormat,
          to: TranscriptFormat,
          inputPath: URL,
          outputPath: URL
      ) throws -> ConversionResult
  }
  ```
- **File:** New `app/Sources/ContextifyCore/TranscriptConverter.swift`
- **Time:** 2 days (includes testing against Python reference implementation)

**2.4 Show progress/status**
- Display toast notification: "Converting transcript..."
- Show success: "Exported to ~/.codex/sessions/.../rollout-*.jsonl"
- Show errors with actionable message
- **File:** Use existing toast system in `ContentView.swift`
- **Time:** 0.5 day

**2.5 Add "Resume" instructions**
- After export, show dialog: "To resume in Codex CLI, run:"
  ```
  cd ~/code/project && codex continue <uuid>
  ```
- Copy-to-clipboard button
- **File:** New alert dialog
- **Time:** 0.5 day

**2.6 Create CLI tool target**
- Add "Command Line Tool" target to Xcode: `contextify-cli`
- Share `TranscriptConverter.swift` between GUI and CLI targets
- CLI `main.swift` with argument parsing (Swift Argument Parser)
- Basic commands:
  ```bash
  contextify convert --from claude-code --to codex <input> [output]
  contextify convert --auto <input>  # Auto-detect format
  contextify --version
  ```
- **File:** New `ContextifyCLI/main.swift`
- **Time:** 1 day

**2.7 CLI installer (GUI app menu item)**
- "Install CLI Tool" menu item in app
- Copies binary to `~/Library/Application Support/Contextify/bin/contextify`
- Makes executable (chmod 755)
- Shows setup assistant:
  - Detects shell (zsh/bash/fish)
  - "Copy Command" button for PATH export
  - "Add to PATH Automatically" button (appends to ~/.zshrc or ~/.bashrc)
  - Verification: "Run `contextify --version` to test"
- **Works for both App Store and direct download** (no sudo, no /usr/local/bin)
- **File:** New `CLIInstaller.swift`
- **Time:** 0.5 day

**Time estimate:** 4-5 days (increased from 3-4 due to Swift converter + CLI)
**Priority:** HIGH (core UX for launch)
**Blocker:** Phase 1 complete

---

## Phase 3: Tool Call Preservation (2-3 days)

### Goal
Convert tool execution history so resumed conversations include "what we already did".

### Tasks

**3.1 Analyze tool call formats**
- Review Claude Code `tool_use` content blocks
- Review Codex `function_call` + `function_call_output` pairs
- Document 1:1 mapping for common tools (Read, Write, Edit, Bash, etc.)
- **Deliverable:** Mapping table in `scripts/TOOL_CALL_MAPPING.md`
- **Time:** 0.5 day

**3.2 Implement Claude Code → Codex tool call conversion**
- Parse `tool_use` blocks from content array
- Generate `function_call` record with:
  - `call_id`: Generate from UUID
  - `name`: Map tool name (Write → write_file, etc.)
  - `arguments`: Extract from `input` field
- Generate `function_call_output` record with:
  - `call_id`: Match function_call
  - `content`: Extract from tool response message
- **File:** Update `scripts/convert_transcript.py`, add `convert_tool_calls()` function
- **Time:** 1 day

**3.3 Implement Codex → Claude Code tool call conversion**
- Parse `function_call` + `function_call_output` pairs
- Generate assistant message with `tool_use` content block:
  - `type`: "tool_use"
  - `id`: Extract from `call_id`
  - `name`: Map tool name (write_file → Write, etc.)
  - `input`: Extract arguments
- Generate assistant message with tool response
- **File:** Update `scripts/convert_transcript.py`
- **Time:** 1 day

**3.4 Test with tool-heavy transcripts**
- Find transcript with 10+ tool calls
- Convert both directions
- Verify tools appear in target CLI
- **Deliverable:** Tool calls preserved in conversions
- **Time:** 0.5 day

**Time estimate:** 2-3 days
**Priority:** MEDIUM (improves context quality)
**Blocker:** Phase 2 complete (so users can actually trigger conversions)

---

## Phase 4: Testing & Polish (2-3 days)

### Goal
Ensure converter is robust and production-ready.

### Tasks

**4.1 Create pytest test suite**
- Test basic message conversion (Claude → Codex, Codex → Claude)
- Test tool call conversion (if Phase 3 complete)
- Test edge cases:
  - Empty content
  - Malformed JSON
  - Missing required fields
  - Very long messages (>10K chars)
  - Special characters in content
- **File:** New `scripts/test_convert_transcript.py`
- **Time:** 1 day

**4.2 Add validation/preview UI**
- Before conversion, show stats:
  - "150 messages, 42 tool calls (will be skipped), 5 file snapshots (dropped)"
  - Estimated time, output file size
- Show warnings for lossy conversions
- "Proceed" / "Cancel" buttons
- **File:** New `TranscriptExportPreviewView.swift`
- **Time:** 1 day

**4.3 Error handling & recovery**
- Detect if target CLI is installed (check `~/.codex/` or `~/.claude/` exists)
- Validate output path is writable
- Catch JSON parse errors gracefully
- Offer to retry on failure
- **File:** Update `TranscriptConverter.swift` wrapper
- **Time:** 0.5 day

**4.4 Documentation pass**
- Update main README with screenshots
- Add troubleshooting section
- Document known limitations prominently
- Add FAQ: "Why aren't tool calls converted?"
- **File:** `README.md`, `scripts/TRANSCRIPT_CONVERTER_README.md`
- **Time:** 0.5 day

**Time estimate:** 2-3 days
**Priority:** MEDIUM (quality assurance)
**Blocker:** Phase 2 complete

---

## Phase 5: Launch Prep (1-2 days)

### Goal
Polish for Show HN announcement.

### Tasks

**5.1 Create demo video/GIF**
- Show unified timeline with both Claude Code and Codex entries
- Right-click → Export to Codex CLI
- Switch to terminal, run `codex continue`
- Show conversation resuming with preserved context
- **Deliverable:** 30-60 second screen recording
- **Time:** 0.5 day

**5.2 Write Show HN post**
- Draft title (see `/tmp/show-hn-contextify-draft.md`)
- Highlight utility and simplicity
- Acknowledge limitations (no tool calls yet)
- Ask for feedback on which conversions matter most
- **Deliverable:** Post ready for submission
- **Time:** 0.5 day

**5.3 Prepare for feedback**
- Monitor HN comments
- Be ready to push quick fixes (typos, doc clarifications)
- Have roadmap ready for "what's next?"
- **Time:** Variable (ongoing)

**Time estimate:** 1-2 days
**Priority:** LOW (polish, not blocking)
**Blocker:** Phase 2 complete

---

## Optional Enhancements (Post-Launch)

### 6.1 Swift Native Converter
- Rewrite `convert_transcript.py` in Swift (~300 lines)
- Bundle with app (no Python dependency)
- Faster conversion (native vs subprocess)
- **Time:** 2-3 days
- **Priority:** LOW (works fine in Python)

### 6.2 Batch Conversion
- Select multiple transcripts → Convert all
- Progress bar for batch operations
- Aggregate stats report
- **Time:** 1 day
- **Priority:** LOW (nice-to-have)

### 6.3 Direct CLI Resumption
- "Export and Resume" button
- Auto-open iTerm2 with `codex continue` command
- Return focus to Contextify after
- **Time:** 1-2 days
- **Priority:** MEDIUM (great UX)

### 6.4 Support More Assistants
- Cursor transcript format
- Aider transcript format
- Generic JSONL → Claude Code converter
- **Time:** 2-3 days per assistant
- **Priority:** LOW (wait for user demand)

---

## Total Time Estimate

| Phase | Days | Priority | Blocking |
|-------|------|----------|----------|
| **Phase 1: Merge to Main** | 1 | HIGH | None |
| **Phase 2: UI + CLI** | 4-5 | HIGH | Phase 1 |
| **Phase 3: Tool Calls** | 2-3 | MEDIUM | Phase 2 |
| **Phase 4: Testing** | 2-3 | MEDIUM | Phase 2 |
| **Phase 5: Launch Prep** | 1-2 | LOW | Phase 2 |
| **Total (MVP)** | **5-6 days** | | Phase 1-2 only |
| **Total (Full)** | **10-14 days** | | All phases |

**MVP = Phase 1 + Phase 2** → Users can convert from UI, basic messages only
**Full = All 5 phases** → Includes tool calls, tests, polish

---

## Recommended Launch Path

### Week 1: MVP (Phase 1-2)
**Day 1:** Merge converter to main, update README
**Day 2-3:** Implement Swift converter (reference Python implementation)
**Day 4:** Build UI integration (menu actions, file picker)
**Day 5:** Create CLI tool target + installer
**Day 6:** Test end-to-end (GUI + CLI), fix bugs

**Deliverable:** Working UI and CLI conversion for basic messages

### Week 2: Quality (Phase 3-4)
**Day 6-8:** Add tool call preservation
**Day 9-10:** Pytest suite, validation UI, error handling

**Deliverable:** Production-ready converter with tool calls

### Week 3: Launch (Phase 5)
**Day 11:** Demo video, finalize Show HN post
**Day 12:** Submit to HN, monitor feedback
**Day 13+:** Iterate based on community response

---

## Success Metrics

**Launch readiness checklist:**
- ✅ Converter merged to main
- ✅ UI menu actions working
- ✅ File picker with auto-generated paths
- ✅ Success/error toast notifications
- ✅ README updated with examples
- ✅ At least 1 real user test (you!) confirms it works
- ⚠️ Tool calls (nice-to-have, not blocking)
- ⚠️ Automated tests (can add post-launch)

**Post-launch goals:**
- 50+ HN upvotes (indicates interest)
- 5+ community feature requests (validates direction)
- 0 critical bugs in converter (basic quality bar)
- At least 1 person successfully resumes conversation across CLIs

---

## Risk Assessment

**Low risk:**
- Phase 1 (merge) - code already works
- Phase 2 UI (Swift wrapper around working Python)

**Medium risk:**
- Phase 3 (tool calls) - complex format mapping, may have edge cases
- Phase 4 (tests) - time-consuming, but straightforward

**High risk:**
- None identified. Worst case: launch with basic messages only, iterate based on feedback.

---

## Decision Points

**Before starting Phase 2:**
- Decide: Python subprocess or Swift rewrite?
- **Recommendation:** Python subprocess initially (faster to ship)

**Before starting Phase 3:**
- Check: Did any HN users ask for tool call support?
- **If no:** Defer Phase 3, ship MVP faster
- **If yes:** Prioritize Phase 3 before launch

**After Phase 2:**
- Check: Are conversions working well enough to launch?
- **If yes:** Consider skipping Phase 3-4, launch as "early preview"
- **If no:** Complete Phase 4 (testing) for confidence

---

## Files to Modify

| Phase | Files | LOC Estimate |
|-------|-------|--------------|
| Phase 1 | `README.md` | +50 |
| Phase 2 | `TranscriptInventoryView.swift` | +150 |
|  | `TranscriptConverter.swift` (new) | +100 |
|  | `ContentView.swift` (toast) | +20 |
| Phase 3 | `scripts/convert_transcript.py` | +200 |
| Phase 4 | `scripts/test_convert_transcript.py` (new) | +300 |
|  | `TranscriptExportPreviewView.swift` (new) | +150 |
| **Total** | | **~970 lines** |

---

## Next Steps (Immediate)

1. Review Show HN draft (`/tmp/show-hn-contextify-draft.md`)
2. Decide on launch timeline (1 week MVP vs 2 weeks full)
3. Create GitHub issues for each phase
4. Start Phase 1: merge feature/transcript-converter to main

**Ready to begin?** Let me know if you want to proceed with Phase 1 now, or if you'd like to adjust the plan.
