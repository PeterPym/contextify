# Claude Code Fixture Transcripts

These fixtures are used for deterministic QA testing of Claude Code transcript discovery.

## Files

- `simple-session.jsonl` - Basic session with user/assistant exchange and search term

## Important Notes

1. **Project directory hash**: The fixture is placed in a directory derived from
   `TEST_PROJECT` using simple `tr '/' '-'` transformation. This is NOT the same
   hash algorithm Claude Code actually uses. Tests validate CWD-based discovery
   logic, not directory hash resolution.

2. **CWD rewriting**: The `cwd` field is rewritten by `seed_fixture_transcript`
   to match `TEST_PROJECT` (default: `/tmp/contextify-qa-test`).

3. **Search terms**: Include `QA_FIXTURE_SEARCH_TERM_CLAUDE` for search tests.

## Cleanup

Fixture seeding is append-only; runs leave transcripts under
`~/.claude/projects/<test-project-hash>/`. Remove those files manually if you
want a clean transcript tree. Cleanup is not automated to avoid touching real
Claude data.

## Creating New Fixtures

1. Copy an existing session from `~/.claude/projects/`
2. Sanitize any sensitive content
3. Add `QA_FIXTURE_SEARCH_TERM_CLAUDE` to a user message for search testing
4. Keep fixtures minimal (2-3 exchanges)
