# Contextify Test Fixtures

This directory contains sample transcript data for testing first-run onboarding flows.

## Structure

```
Fixtures/transcripts/
├── claude/
│   └── projects/
│       └── demo-project-001.jsonl    # Claude Code format sample
└── codex/
    └── sessions/
        └── demo-session-001.jsonl     # Codex CLI format sample
```

## Usage

These fixtures are automatically used by the `seed-demo` command in `scripts/xc.sh`:

```bash
./scripts/xc.sh seed-demo
```

This will:
1. Create a temporary demo directory with these fixtures
2. Symlink `~/.claude/projects` and `~/.codex/sessions` to the demo data
3. Allow for reproducible, fast first-run testing (<10s)

## Transcript Formats

- **Claude Code**: Uses top-level `uuid` and `type` fields, `text` content blocks
- **Codex**: Uses `messageId` with `payload.type`, `input_text`/`output_text` content blocks

**Format specifications:**
- `build/docs/specifications/transcript-formats.md` - Overview and comparison
- `build/docs/specifications/claude-code-transcript-format.md` - Claude Code detailed spec
- `build/docs/specifications/codex-cli-transcript-format.md` - Codex CLI detailed spec
