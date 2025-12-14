---
todo_id: CONTEXT-REINJECTION
title: Reference - Installing skills in Claude Code
type: reference
date: 2025-12-13
status: active
description: Reference notes for installing skills into Claude Code, used to scope Phase 2 skill distribution and documentation.
sources:
  - https://github.com/anthropics/skills
  - https://support.claude.com/en/articles/12512176-what-are-skills
  - https://support.claude.com/en/articles/12512180-using-skills-in-claude
  - https://code.claude.com/docs/en/skills
---

# Reference: installing skills in Claude Code

This document captures the current official installation guidance that is relevant to Phase 2. It is intentionally concise and should be refreshed if Anthropic changes their install flow.

Phase 2 prefers plugin-based distribution for Contextify skills. Filesystem installs (`~/.claude/skills/`) are a fallback.

## Contextify plugin install (Phase 2)

Phase 2 ships a Claude Code plugin from this repository via a marketplace:

```text
/plugin marketplace add PeterPym/contextify
/plugin install contextify@peterpym-contextify
```

Claude Code requires a restart after installing a plugin.

## Claude Code plugin marketplace install (Anthropic skills repo)

From `https://github.com/anthropics/skills`:

1) Add the repository as a plugin marketplace:

```text
/plugin marketplace add anthropics/skills
```

2) Browse and install:

- Select “Browse and install plugins”
- Select `anthropic-agent-skills`
- Select a skill set (e.g. `document-skills` or `example-skills`)
- Select “Install now”

3) Or install directly:

```text
/plugin install document-skills@anthropic-agent-skills
/plugin install example-skills@anthropic-agent-skills
```

## Missing: dedicated “install your own skill” docs (TO ADD)

The Contextify Phase 2 plan needs an explicit “install a local custom skill” flow for Claude Code. If Anthropic publishes a definitive doc for that workflow, add it here as a Markdown reference.

## Filesystem installs for Claude Code

Claude Code also discovers skills from the filesystem:

- Personal: `~/.claude/skills/`

This flow is described in `build/notes/todo-support/CONTEXT-REINJECTION-agent-skills-developer-guide-reference.md` and is validated during Phase 2 QA.
