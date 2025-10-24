# Transcript Converter QA Directory

**Purpose:** Quality assurance testing for the cross-CLI transcript converter.

## Directory Contents

```
build/qa/transcript-converter/
├── README.md                      # This file
├── TEST-PLAN.md                   # Comprehensive test plan
├── RESULTS.md                     # Test execution results (to be created)
├── generate_test_transcript.py    # Test transcript generator
├── fixtures/                      # Generated test transcripts
│   ├── test-claude-*.jsonl       # Claude Code format test files
│   └── test-codex-*.jsonl        # Codex CLI format test files
└── outputs/                       # Conversion test outputs
    ├── converted-to-codex.jsonl  # Claude → Codex conversions
    └── converted-to-claude.jsonl # Codex → Claude conversions
```

## Quick Start

### Generate Test Transcript (Claude Code)
```bash
./build/qa/transcript-converter/generate_test_transcript.py \
  --format claude-code \
  --output build/qa/transcript-converter/fixtures/test-$(date +%Y%m%d-%H%M%S).jsonl
```

This automatically:
- Creates a fixture file with test conversation
- Copies to `~/.claude/projects/-Users-rob-code-projects-contextify/<uuid>.jsonl`
- Shows resume command

### Generate Test Transcript (Codex)
```bash
./build/qa/transcript-converter/generate_test_transcript.py \
  --format codex \
  --output build/qa/transcript-converter/fixtures/test-codex-$(date +%Y%m%d-%H%M%S).jsonl
```

Then manually copy to Codex sessions directory (see output for instructions).

### Run Conversion Test
```bash
# Claude Code → Codex
./scripts/convert_transcript.py \
  --from claude-code \
  --to codex \
  build/qa/transcript-converter/fixtures/test-claude-*.jsonl \
  build/qa/transcript-converter/outputs/converted-to-codex.jsonl

# Codex → Claude Code (tests UUID auto-correction)
./scripts/convert_transcript.py \
  --from codex \
  --to claude-code \
  build/qa/transcript-converter/fixtures/test-codex-*.jsonl \
  build/qa/transcript-converter/outputs/arbitrary-name.jsonl
```

## Test Workflow

1. **Read TEST-PLAN.md** - Understand all test categories
2. **Generate fixtures** - Create test transcripts using generator script
3. **Execute tests** - Follow test plan categories 1-7
4. **Document results** - Record pass/fail in RESULTS.md
5. **Commit findings** - Update converter or docs based on results

## Generator Script Usage

```bash
./generate_test_transcript.py --help

Options:
  --format {claude-code,codex}  Transcript format to generate
  --output OUTPUT               Output file path
  --project-dir PATH            Project directory (default: /Users/rob/code/projects/contextify)
  --git-branch BRANCH           Git branch name (default: feature/swift-cli-converter)
  --git-commit HASH             Git commit hash (default: c78e2dd)
  --exchanges NUM               Number of conversation exchanges (default: 2)
```

## Test Categories (Summary)

See TEST-PLAN.md for full details:

1. **Format Validation** - Generated transcripts match actual CLI formats
2. **CLI Resumption** - Both CLIs can resume generated sessions
3. **Conversion (Claude → Codex)** - Conversion works correctly
4. **Conversion (Codex → Claude)** - UUID auto-correction works
5. **Round-Trip** - Data preserved through bidirectional conversion
6. **Edge Cases** - Error handling for malformed inputs
7. **Directory Sensitivity** - Resume requires correct project directory

## Related Documentation

- **Converter README:** `scripts/TRANSCRIPT_CONVERTER_README.md`
- **Test Plan:** `build/qa/transcript-converter/TEST-PLAN.md`
- **Format Spec (Claude Code):** `build/notes/technical-reference/claude-code-transcript-format.md`
- **Format Comparison:** `build/notes/archive/technical-briefing-local-history-claude-code-codex.md`
- **Resume Guide:** `build/notes/technical-reference/transcript-resumption-guide.md`

## Success Criteria

✅ QA complete when:
- All test categories pass
- Both CLIs resume converted sessions
- Round-trip preserves content
- Edge cases handled gracefully
- RESULTS.md documents findings
- Any bugs fixed or documented as known limitations
