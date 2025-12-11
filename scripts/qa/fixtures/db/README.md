# Database Fixture Files

These fixtures are used for testing database migrations and integrity.

## Files

- `v16-contextify.db` - Oldest supported schema (collapsed baseline)
- `v25-contextify.db` - Pre-FTS5 schema (tests search index creation)

## Creating New Fixtures

1. Build and run an older version of Contextify
2. Let it create a database with some test data
3. Copy the database file: `cp ~/Library/Application\ Support/Contextify/contextify.db v{VERSION}-contextify.db`
4. Remove WAL/SHM files if present
5. Optionally sanitize sensitive data

## Usage

The `install_db_fixture` helper in `lib/common.sh` handles:
- Backing up the current database
- Installing the fixture
- Cleaning up WAL/SHM files

The `restore_db_from_backup` helper restores the original database.

## Schema Version History

| Version | Description |
|---------|-------------|
| v16 | Collapsed baseline (original migrations merged) |
| v25 | Pre-FTS5 schema |
| v26 | Current schema with FTS5 search index |
