# contextify-ingest CLI

Cross-platform CLI for ingesting Claude Code and Codex transcripts into a SQLite database.

## Installation

### Linux (x86_64 / arm64)

```bash
# One-liner install (latest version)
curl -fsSL https://raw.githubusercontent.com/banagale/contextify/main/scripts/build/install-cli.sh | bash

# Specific version
curl -fsSL https://raw.githubusercontent.com/banagale/contextify/main/scripts/build/install-cli.sh | bash -s -- 1.0.0

# Manual download
curl -fsSL https://github.com/banagale/contextify/releases/download/cli-v1.0.0/contextify-linux-x86_64.tar.gz | tar xz
sudo mv contextify-ingest /usr/local/bin/
```

### macOS

macOS users should use the [Contextify app](https://contextify.sh) instead, which provides the same ingestion with a native HUD interface.

## Usage

### Basic Ingestion

```bash
# Discover transcripts (dry run)
contextify-ingest discover

# Ingest all transcripts
contextify-ingest ingest --db ~/contextify.db

# Verify database integrity
contextify-ingest verify --db ~/contextify.db
```

### Options

```bash
# Ingest from specific paths
contextify-ingest ingest --db ~/contextify.db --input ~/.claude/projects/my-project

# Filter by provider
contextify-ingest ingest --db ~/contextify.db --provider claude
contextify-ingest ingest --db ~/contextify.db --provider codex

# Only process recent transcripts
contextify-ingest ingest --db ~/contextify.db --since 2024-01-15
contextify-ingest ingest --db ~/contextify.db --since 1705363200  # Unix timestamp

# Full rebuild (clear existing data)
contextify-ingest ingest --db ~/contextify.db --full-rebuild

# JSONL output for scripting
contextify-ingest ingest --db ~/contextify.db --format jsonl
```

### Commands

| Command | Description |
|---------|-------------|
| `discover` | Find transcripts without ingesting |
| `ingest` | Parse and store transcripts in database |
| `verify` | Check database integrity |
| `schema dump` | Export database schema |

### Ingest Options

| Option | Description |
|--------|-------------|
| `--db PATH` | SQLite database file path (required) |
| `--input PATH...` | Custom paths to scan (default: ~/.claude/projects, ~/.codex/sessions) |
| `--provider TYPE` | Filter by provider: auto, claude, or codex |
| `--since DATE` | Only process transcripts modified after this time |
| `--full-rebuild` | Clear existing data before ingesting |
| `--format TYPE` | Output format: human or jsonl |
| `--workers N` | Parallel workers (default: 4, not yet implemented) |

## Database

The CLI produces a SQLite database compatible with the Contextify macOS app. Key tables:

- `projects` - Project metadata
- `transcripts` - Transcript file records
- `transcript_entries` - Individual conversation turns
- `transcript_entries_fts` - Full-text search index

### Example Queries

```sql
-- Count entries by project
SELECT p.name, COUNT(e.id) as entries
FROM projects p
JOIN transcripts t ON t.project_id = p.id
JOIN transcript_entries e ON e.transcript_id = t.id
GROUP BY p.id
ORDER BY entries DESC;

-- Full-text search
SELECT e.content
FROM transcript_entries_fts
WHERE content MATCH 'error handling'
LIMIT 10;

-- Recent activity
SELECT t.file_path, t.last_modified
FROM transcripts t
ORDER BY t.last_modified DESC
LIMIT 10;
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (parse failures, database issues) |

## Version

```bash
contextify-ingest --version
# Output: 1.0.0 (schema v32)
```

## Troubleshooting

### Database locked

If you see "database is locked", ensure no other process is accessing the database file.

### Missing transcripts

Check that:
1. Transcripts are in `~/.claude/projects/` or `~/.codex/sessions/`
2. Files have `.jsonl` extension
3. Use `--input` to scan custom paths

### Schema mismatch

If using a database created by a different Contextify version, use `--full-rebuild` to recreate:

```bash
contextify-ingest ingest --db ~/contextify.db --full-rebuild
```
