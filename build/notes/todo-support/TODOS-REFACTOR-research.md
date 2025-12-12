---
todo_id: P2-TODOS-REFACTOR
title: TODO System Refactoring Research
type: research
date: 2025-12-03
status: active
description: Research on Claude Code task management patterns in 2025
---

# TODO System Refactoring Research

## Problem Statement

Current TODOS.md is 2k+ lines with these pain points:

1. **File too large** - AI reads full file to update one status
2. **Priority embedded in ID** - e.g., `#P1-WEBSITE` requires renaming to reprioritize
3. **No clear rules** on when entry needs backing file
4. **Ad-hoc detail files** - inconsistent structure in `build/notes/todo-support/`

## Research: Claude Code Task Management in 2025

### The Core Problem

Claude Code's built-in TODO list doesn't persist across sessions. When context fills up and you `/compact` or `/clear`, it's gone. So people use in-repo files, but those get bloated.

---

### Pattern 1: Hierarchical Split (Most Common)

**Zhu Liang's approach** from [The Ground Truth](https://thegroundtruth.substack.com/p/my-claude-code-workflow-and-personal-tips):

```
├── ROADMAP.md              # ~50 lines, high-level bullets only
├── tasks/
│   ├── 001-db.md           # Full PRD + implementation details
│   ├── 002-source-lib.md
│   └── ...
├── AD_HOC_TASKS.md
├── BUGS.md
```

**Key insight:** ROADMAP.md is explicitly imported in CLAUDE.md via `@reference/ROADMAP.md`. AI reads the small file first, loads detail files only when working on that task.

---

### Pattern 2: Checkbox + Archive (Simplest)

**Ben Newton's approach** from [benenewton.com](https://benenewton.com/blog/claude-code-roadmap-management):

```markdown
# ROADMAP.md

## High Priority
- [ ] Fix settings window
- [-] 2025/12/03 Website screenshots

## Recently Completed
- [x] 2025/12/03 Design system migration
```

**Rules:**
- `[ ]` = todo, `[-]` = in progress, `[x]` = done
- One emoji + date, nothing more
- Move completed to archive file when it grows

---

### Pattern 3: GitHub Issues as Database (Most Sophisticated)

**Claude Code PM (CCPM)** from [automazeio/ccpm](https://github.com/automazeio/ccpm):

```
.claude/
├── epics/
│   └── [epic-name]/
│       ├── epic.md         # Implementation plan
│       ├── 1.md            # Task 1 details
│       └── 2.md            # Task 2 details
├── prds/                   # Product requirements
└── commands/pm/            # /pm:next, /pm:blocked, etc.
```

**Key insight:** Local markdown is working draft. GitHub Issues is the persistent database. AI syncs incrementally via `/pm:issue-sync`. Multiple agents can work in parallel because each reads only its task file.

---

### Pattern 4: Full Framework (Simone)

**Simone** from [Helmi/claude-simone](https://github.com/Helmi/claude-simone):

Two versions:
- **Legacy:** Directory-based task management (proven, stable)
- **MCP Server:** New Model Context Protocol implementation (early access)

Heavier setup but provides structured prompts, activity tracking, and sub-agent coordination.

---

### Comparison Table

| Pattern | Index File | Detail Files | Priority | Complexity |
|---------|-----------|--------------|----------|------------|
| Zhu Liang | ROADMAP.md (~50 lines) | `/tasks/*.md` | By section | Low |
| Ben Newton | ROADMAP.md (single file) | None (inline) | By section | Minimal |
| CCPM | GitHub Issues | `/epics/**/*.md` | Labels/fields | High |
| Simone | MCP or directory index | Per-task files | Metadata | High |

**All avoid priority-in-ID problem:** Priority is either a section header or a metadata field.

---

## Proposed Approaches for Contextify

### Option A: JSON Index + Markdown Details

```
todos/
├── index.json        # ~100 lines: {id, title, priority, status}
└── active/
    ├── WEBSITE.md
    ├── SETTINGS.md
    └── ...
```

**index.json example:**
```json
{
  "todos": [
    {"id": "WEBSITE", "priority": 1, "status": "in_progress", "title": "Complete website with screenshots"},
    {"id": "SETTINGS", "priority": 0, "status": "open", "title": "Fix Settings window and permissions UX"}
  ]
}
```

**Pros:**
- Machine-parseable, easy priority changes
- AI reads ~50 lines for overview
- Details loaded only when needed

**Cons:**
- JSON less human-friendly to edit
- Two formats to maintain

### Option B: Minimal Markdown Index + Details (Zhu Liang Style)

```
├── TODOS.md          # Just titles + status, ~100 lines
└── todos/
    ├── WEBSITE.md
    ├── SETTINGS.md
    └── ...
```

**TODOS.md example:**
```markdown
# P0 - Launch Critical
- [ ] SETTINGS: Fix Settings window and permissions UX
- [ ] PROJECT-ROOT: Fix spurious project root modal

# P1 - High Priority
- [-] WEBSITE: Complete website with screenshots
- [ ] SPARKLE: Extend release.py with Sparkle signing
```

**Pros:**
- Pure markdown, human-friendly
- Priority change = move line between sections
- Familiar checkbox syntax

**Cons:**
- Still requires parsing sections for priority
- Less structured than JSON

### Option C: CCPM-Style with GitHub Issues

Use GitHub Issues as the database, local markdown as drafts.

**Pros:**
- External visibility for collaborators
- Parallel agent support
- Rich querying via `gh` CLI

**Cons:**
- Adds external dependency
- Not purely in-repo text
- More complex setup

---

## Recommendation

**Start with Option B** (Minimal Markdown Index):
1. Lowest friction migration from current system
2. Human-readable, git-diffable
3. Can evolve to JSON index later if needed

**Migration steps:**
1. Create `todos/` directory for detail files
2. Create slim `TODOS.md` with just ID + title + checkbox
3. Move detail content to `todos/{ID}.md` files
4. Update AGENTS.md to reference new structure
5. Archive completed items to `todos/archive/`

---

## Sources

- [My Claude Code Workflow - Zhu Liang](https://thegroundtruth.substack.com/p/my-claude-code-workflow-and-personal-tips)
- [Claude Code Roadmap Management - Ben Newton](https://benenewton.com/blog/claude-code-roadmap-management)
- [Claude Code PM (CCPM)](https://github.com/automazeio/ccpm)
- [Simone Framework](https://github.com/Helmi/claude-simone)
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code)
- [Claude Code Best Practices - Anthropic](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Managing Claude Code Context - MCPcat](https://mcpcat.io/guides/managing-claude-code-context/)
