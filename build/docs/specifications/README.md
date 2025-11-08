# Specifications

External dependency format specifications.

## Purpose

This directory contains documentation for data formats and protocols that Contextify consumes but does not control:
- Claude Code transcript format (JSONL)
- Codex CLI transcript format (JSONL)
- External API contracts

These are **stable reference documents** for external formats, not internal implementation specs.

## Documents

### [Claude Code Format](claude-code-format.md)
**Topics:** Claude Code JSONL transcript format specification
- Message structure and record types
- Content block types (`text`, `tool_use`, `tool_result`)
- Metadata records (`file-history`, `summary`, `system`)
- Transcript classification guide
- Field reference by classification

**Key Differences from Codex:**
- Claude Code uses `text` content blocks
- Claude Code has top-level `uuid`/`type` fields
- Message structure differs in payload wrapping

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

---

## Note on Codex Format

Currently missing: **codex-format.md** (TODO: extract from existing docs)

See TECHNICAL-DOCS-AUDIT-2025-11-08.md for recommendation to create this file.
