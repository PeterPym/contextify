# Specifications

External dependency format specifications.

## Purpose

This directory contains documentation for data formats and protocols that Contextify consumes but does not control:
- Claude Code transcript format (JSONL)
- Codex CLI transcript format (JSONL)
- External API contracts

These are **stable reference documents** for external formats, not internal implementation specs.

## Documents

### [Transcript Formats Overview](transcript-formats.md)
**Topics:** High-level comparison of Claude Code and Codex CLI transcript formats
- Storage locations and project discovery
- Record type taxonomies
- Message linking strategies
- Format comparison table
- Critical requirements (monotonic timestamps)

### [Claude Code Transcript Format](claude-code-transcript-format.md)
**Topics:** Complete Claude Code JSONL transcript format specification
- Message structure and record types
- Content block types (`text`, `tool_use`, `tool_result`, `thinking`, `image`)
- Metadata records (`file-history-snapshot`, `summary`, `system`)
- Usage metadata and token counting
- Transcript corruption patterns (Claude Code Web)
- Tool call handshake protocol

### [Codex CLI Transcript Format](codex-cli-transcript-format.md)
**Topics:** Complete Codex CLI JSONL transcript format specification
- Storage location and directory structure requirements
- Session discovery requirements (6 critical rules)
- System-injected messages detection pattern
- Record types (`session_meta`, `response_item`, `event_msg`, `turn_context`, `function_call`, `reasoning`)
- Event types and telemetry stream
- Validation checklist and troubleshooting

**Key Format Differences:**
- **Content blocks:** Claude Code uses `text`, Codex uses `input_text`/`output_text`
- **Message IDs:** Claude Code has top-level `uuid`, Codex uses `payload` structure
- **Storage:** Claude Code per-project directories, Codex global date-hierarchical
- **Tool invocations:** Claude Code uses content blocks, Codex has first-class `function_call` records
- **Session context:** Claude Code implicit, Codex has explicit `session_meta` record

---

## Relationship to Other Docs

- **Components/** - Components that parse these formats (HooverEngine, TranscriptParsers)
- **Architecture/** - System design assumes these format specs
- **Guides/** - How to work with these formats (transcript resumption, etc.)

---

## Updating These Docs

**When to update:**
- When Claude Code or Codex CLI changes their transcript format (external change)
- When we discover undocumented fields or edge cases through usage

**What to include:**
- Complete field specifications
- Record type taxonomy
- Examples of each record type
- Known variations and edge cases

**What NOT to include:**
- How Contextify parses these formats (that's in Components/)
- Implementation details of our parsers (that's in Components/)
- Gap analyses or feature requests (use /tmp/ or TODOS.md)

