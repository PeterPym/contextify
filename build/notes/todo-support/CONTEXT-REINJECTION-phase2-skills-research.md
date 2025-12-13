---
todo_id: CONTEXT-REINJECTION
title: Phase 2 research - Skills adoption (Codex CLI + Claude Code)
type: research
date: 2025-12-13
status: active
description: Research notes on skills adoption in Codex CLI and Claude Code, and implications for Contextify Phase 2 (skills-first + CLI install story).
sources:
  - https://simonwillison.net/2025/Dec/12/openai-skills/
  - https://github.com/openai/codex/blob/main/docs/skills.md
  - https://github.com/openai/codex/pull/7412
  - https://github.com/anthropics/skills
  - https://support.claude.com/en/articles/12512176-what-are-skills
  - https://support.claude.com/en/articles/12512198-creating-custom-skills
---

# Phase 2 research: Skills adoption (Codex CLI + Claude Code)

## Findings

### Codex CLI

Codex CLI supports an experimental skills mechanism:

- Skills live under `~/.codex/skills/**/SKILL.md` (recursive).
- Each skill is a directory with a `SKILL.md` file containing YAML frontmatter:
  - required keys: `name`, `description`
- Codex injects only name/description/path into the runtime context at startup; the body stays on disk until needed.

This enables progressive disclosure: a large library of procedural guidance exists on disk without bloating the prompt.

### ChatGPT code execution environment

ChatGPT’s code execution environment includes built-in skills under `/home/oai/skills` (PDF/DOCX/spreadsheets guidance and scripts). The content is procedural playbooks, not just “prompting tips”.

### Claude / Claude Code

Anthropic treats skills as composable “procedural knowledge + resources/scripts” that an agent loads dynamically. Their public `anthropics/skills` repository documents installation into Claude Code via plugin marketplace commands.

## Implications for Contextify

Skills are a strong adoption mechanism for Contextify reinjection:

- The hard part is not “how to run a command”, it is encoding the reliable workflow and guardrails:
  - when to query
  - which scope/time window to use
  - how to budget output
  - how to handle errors deterministically
- Phase 2 can ship value without adding a new transport (MCP) by focusing on:
  - Codex/Claude Code skills that teach `contextify-query` usage
  - CLI distribution/install so tools can invoke it reliably
