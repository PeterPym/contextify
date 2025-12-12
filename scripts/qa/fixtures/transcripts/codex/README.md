# Codex CLI Fixture Transcripts

Fixtures for deterministic QA testing of Codex CLI transcript discovery.

## Generating Fixtures

**Never manually create JSONL files.** Always generate via CLI:

```bash
./scripts/qa/fixtures/generate-fixtures.sh
```

This creates real transcripts using the Codex CLI with proper session structure.

## Expected Files (after generation)

- `project1.jsonl` - Project 1 (both providers), includes QA_FIXTURE_SEARCH_TERM_CODEX
- `project3.jsonl` - Project 3 (Codex only)

## How Seeding Works

The `seed_fixture_transcript` function in `common.sh`:
1. Copies the fixture to `~/.codex/sessions/YYYY/MM/DD/`
2. Rewrites the `cwd` field to match the target project path
3. Uses current date for the directory structure

## Cleanup

Seeded transcripts create `qa-fixture-*.jsonl` files in the date-based directory.
Use `--isolate` mode which backs up and restores production data, or manually
remove test files.

## References

- `build/docs/specifications/transcript-formats.md` - Format specification
- `appstore-metadata/review-materials/generate-transcripts.sh` - Reference implementation
