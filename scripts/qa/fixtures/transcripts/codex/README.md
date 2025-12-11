# Codex CLI Fixture Transcripts

These fixtures are used for deterministic QA testing of Codex CLI transcript discovery.

## Files

- `simple-session.jsonl` - Basic session with user/assistant exchange and search term

## Important Notes

1. **Date-based paths**: Codex stores transcripts in `~/.codex/sessions/YYYY/MM/DD/`.
   The `seed_fixture_transcript` helper creates this structure dynamically.

2. **CWD rewriting**: The `cwd` field is rewritten by `seed_fixture_transcript`
   to match `TEST_PROJECT` (default: `/tmp/contextify-qa-test`).

3. **Search terms**: Include `QA_FIXTURE_SEARCH_TERM_CODEX` for search tests.

## Cleanup

Fixture seeding is append-only; runs leave `qa-fixture-*.jsonl` files under
`~/.codex/sessions/YYYY/MM/DD/`. Remove those files manually if you want to
prune old runs. Cleanup stays manual to avoid deleting real Codex transcripts.

## Creating New Fixtures

1. Copy an existing session from `~/.codex/sessions/`
2. Sanitize any sensitive content
3. Add `QA_FIXTURE_SEARCH_TERM_CODEX` to a user message for search testing
4. Keep fixtures minimal (2-3 exchanges)
