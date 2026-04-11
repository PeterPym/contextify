## Contextify 1.5.0

### Contextify Cloud

Contextify Cloud is here. Push your conversation database to the cloud and search it from any device. Per-project sync controls let you choose exactly what gets synced. 14-day free trial, no credit card required.

- Cloud sync with progress tracking and ETA estimation
- Per-project opt-in/out controls for privacy
- Team management with seat-based billing
- CLI `cloud push`, `cloud pull`, and `cloud status` commands
- Device provenance tracking across machines

### Search Quality

- Porter stemming for better natural-language matching ("deploy" finds "deployed", "deployment")
- Git-anchored search: find conversations by the files they touched (`--anchor-files`)
- FTS5 hyphen pre-processing for queries like "pre-commit" and "e2e"
- Improved handling of parentheses and unbalanced quotes

### CLI Improvements

- `--hours`, `--since`, `--until` time filtering
- Short UUID prefixes for entry and context commands (8 characters)
- Fuzzy project name suggestions on typo
- Search scope summary showing entry, project, and device counts
- Data freshness indicator in status output
- Cloud commands available from the macOS CLI

### New Features

- Menu bar mode with background utility operation
- Launch at Login support (DMG and App Store)
- Transcript tagging for excluding benchmarks from search
- Sidechain transcript discovery (subagents/)
- Proof-of-concept Gemini CLI and OpenCode transcript format support

### Reliability

- Cloud sync chunks large queries to stay under SQLite's 999-parameter limit
- Automatic retry on transient 502/503/504 server errors
- Graceful deferral when ingest is in progress
- Settings window stays above main window with Keep on Top enabled

### Full changelog

[v1.3.2...v1.5.0](https://github.com/PeterPym/contextify/compare/v1.3.2...v1.5.0)
