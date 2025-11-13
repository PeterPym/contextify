# Transcript Analysis Workflow (For Agents)

When working with Claude Code transcript files, **ALWAYS classify first** before analyzing structure.

## Classification Scripts

### Simple (Fast)

```bash
./scripts/classify_transcript.sh <transcript-id-or-file-path>
```

**Returns:** `"conversational"` | `"metadata-only"` | `"empty"`

### Detailed (Multi-dimensional)

```bash
./scripts/classify_transcript_detailed.sh <transcript-id-or-file-path>
```

**Returns:** Primary classification + 4 dimensional axes (conversation, metadata, content_flags, state)

## Agent Workflow

### Step 1: Classify

```bash
./scripts/classify_transcript.sh A31F3D0A-4820-41AB-8121-0C81AC8533C4
```

### Step 2: Read Relevant Documentation

| Classification | Read These Sections | Parser Fields |
|---------------|---------------------|---------------|
| **conversational** | `claude-code-transcript-format.md` §1-2 (User/Assistant Messages) | `uuid`, `timestamp`, `type`, `message` |
| **metadata-only** | `claude-code-transcript-format.md` §3-5 (File-History, Summary, System) | `messageId`, `snapshot`, `trackedFileBackups` |
| **empty** | (no further analysis) | (none) |

### Step 3: Reference Implementation

- **Parser:** `app/Sources/ContextifyCore/Database/TranscriptParsers.swift`
- **Database:** `app/Sources/ContextifyCore/Database/DatabaseSchema.swift`

## Key Documentation

**Primary resource:** `build/docs/specifications/claude-code-format.md`

This document contains:
- Complete field specifications for all record types
- Transcript Classification Guide (§ at end)
- Field Reference by Classification table
- Content block types and structures

**DO NOT** guess at transcript structure - classify first, then read the appropriate section.

## Additional Resources

**For all transcript work (parsing, discovery, permissions):**
- **ALWAYS consult** `build/docs/specifications/transcript-formats.md` FIRST
  - Storage locations (Claude Code vs Codex)
  - Project discovery (directory vs `cwd` field)
  - Record types and content blocks
  - Format comparison table

**For transcript corruption issues:**
- See `build/docs/operations/transcript-corruption-detection.md`
- Detection script: `scripts/transcript-repair/repair_transcript.py --dry-run`
- Repair script: `scripts/transcript-repair/repair_transcript.py`

## Common Pitfalls

❌ **Don't:**
- Guess at transcript structure without classifying first
- Assume all transcripts have conversational content
- Parse JSONL directly without checking format spec
- Use directory structure for Codex project discovery

✅ **Do:**
- Classify first, then read relevant documentation
- Check transcript-formats.md for storage locations
- Use classification scripts for quick analysis
- Reference parser implementation for field mapping
