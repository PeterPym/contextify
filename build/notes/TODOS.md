---
title: Task Management
type: reference
related: ROADMAP.md
description: Tasks are now managed via Bloon CLI. This file provides quick reference.
migrated_to: bloon
migration_date: 2026-01-17
archive: build/notes/archive/TODOS-archived-2026-01-17.md
---

# Task Management

Tasks are now managed via **Bloon CLI** (cross-project task management).

## Quick Commands

```bash
# What's ready to work on?
bloon ready -p contextify

# View by priority
bloon list -p contextify --priority 0   # P0 - critical
bloon list -p contextify --priority 1   # P1 - high
bloon list -p contextify --priority 2   # P2 - medium

# Add a task
bloon add "Task title" -p contextify --priority 1 --tags feature

# Complete a task
bloon done bl-XXXX --note "Merged in PR #123"

# Search tasks
bloon search "keyword" -p contextify

# Show task details
bloon show bl-XXXX
```

## Priority Levels

| Priority | Meaning |
|----------|---------|
| P0 | Launch critical - release blockers |
| P1 | High priority - ship soon after launch |
| P2 | Medium priority - can defer |
| P3 | Low priority / deferred |

## Exploratory Ideas

See [ROADMAP.md](ROADMAP.md) for P4-P5 items (research/exploratory work not yet scoped for implementation).

## Archive

The original TODOS.md (3000+ lines) was archived on 2026-01-17:
`build/notes/archive/TODOS-archived-2026-01-17.md`

## Bloon Documentation

- CLI help: `bloon --help`
- Project: `~/code/projects/bloon`
