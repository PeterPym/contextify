# Transcript Management Scripts

This directory contains scripts for managing Claude Code and Codex CLI transcripts.

## Scripts

### recover-from-isolation.sh

Safely recovers transcripts when isolated by QA testing or demo recording.

**Purpose:** Merges and restores Claude Code and Codex transcripts after QA/demo isolation, using V3 safety principles (atomic swaps, conflict preservation, rollback).

**Usage:**
```bash
# Check current isolation status
./scripts/transcripts/recover-from-isolation.sh --audit

# Preview recovery
./scripts/transcripts/recover-from-isolation.sh --dry-run

# Execute recovery (interactive)
./scripts/transcripts/recover-from-isolation.sh

# Execute recovery (non-interactive)
./scripts/transcripts/recover-from-isolation.sh --yes

# Recover only Claude transcripts
./scripts/transcripts/recover-from-isolation.sh --claude-only

# Recover only Codex transcripts
./scripts/transcripts/recover-from-isolation.sh --codex-only
```

**Safety features:**
- Atomic rename swaps (crash-safe)
- Conflict preservation via rsync `--backup-dir`
- 7-day rollback snapshots (`.PREMERGE-*` directories)
- Corruption detection (empty files, invalid JSON)
- Duplicate filename checking

**See also:**
- `build/docs/operations/transcript-corruption-detection.md`
- `scripts/qa/lib/common.sh` (QA isolation logic)
- `scripts/release/demo-recording.sh` (Demo isolation logic)

---

### classify_transcript.sh

Classifies transcript files by examining their structure.

**Purpose:** Identifies transcript format (Claude Code vs Codex CLI), checks for conversation data and metadata, and determines classification (conversational, metadata-only, or empty).

**Usage:**
```bash
# Classify by file path
./scripts/transcripts/classify_transcript.sh /path/to/transcript.jsonl

# Classify by transcript ID (requires database)
./scripts/transcripts/classify_transcript.sh A31F3D0A-4820-41AB-8121-0C81AC8533C4
```

**Returns JSON with:**
- `type`: "claude-code" | "codex-cli" | "unknown"
- `has_conversation`: boolean
- `has_metadata`: boolean
- `record_types`: array of record types found
- `classification`: "conversational" | "metadata-only" | "empty"

**See also:**
- `build/docs/guides/TRANSCRIPT-ANALYSIS.md` (full workflow)
- `build/docs/specifications/transcript-formats.md` (format specs)

---

### classify_transcript_detailed.sh

Extended version of `classify_transcript.sh` with detailed analysis.

**Purpose:** Provides comprehensive transcript analysis including record counts, conversation structure, and format-specific details.

**Usage:** Same as `classify_transcript.sh`

**Returns:** Detailed JSON with record counts, timestamps, and structure information.

---

## Related Documentation

- **Transcript formats:** `build/docs/specifications/transcript-formats.md`
- **Analysis workflow:** `build/docs/guides/TRANSCRIPT-ANALYSIS.md`
- **Corruption detection:** `build/docs/operations/transcript-corruption-detection.md`
- **Claude Code format:** `build/docs/specifications/claude-code-transcript-format.md`

## Related Scripts

- **QA isolation:** `scripts/qa/lib/common.sh` - Backup/restore for QA tests
- **Demo isolation:** `scripts/release/demo-recording.sh` - Backup/restore for demo recording
- **Database management:** `scripts/db_manager.sh` - Database operations
- **Transcript repair:** `scripts/transcript-repair/` - Repair tools for corrupted transcripts
