# Claude Code Fixture Transcripts

Fixtures for deterministic QA testing of Claude Code transcript discovery.

## Generating Fixtures

**Never manually create JSONL files.** Always generate via CLI:

```bash
./scripts/qa/fixtures/generate-fixtures.sh
```

This creates real transcripts using the Claude CLI with proper multi-turn conversations.

## Expected Files (after generation)

- `project1.jsonl` - Project 1 (both providers), includes QA_FIXTURE_SEARCH_TERM_CLAUDE
- `project2.jsonl` - Project 2 (Claude only)

## How Seeding Works

The `seed_fixture_transcript` function in `common.sh`:
1. Copies the fixture to `~/.claude/projects/<hash>/`
2. Rewrites the `cwd` field to match the target project path
3. Hash is derived via `tr '/' '-'` (simplified, not Claude's actual algorithm)

## Cleanup

Seeded transcripts persist in `~/.claude/projects/<hash>/`. Use `--isolate` mode
which backs up and restores production data, or manually remove test directories.

## References

- `build/docs/specifications/transcript-formats.md` - Format specification
- `appstore-metadata/review-materials/generate-transcripts.sh` - Reference implementation
