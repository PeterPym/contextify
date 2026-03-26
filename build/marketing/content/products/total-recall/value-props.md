# Total Recall: Value Propositions

## One-liner

Your AI can search every past AI session from the current one.

## Elevator pitch

Total Recall gives your Claude Code and Codex sessions long-term memory. Your current AI session can look up decisions, code patterns, and solutions from weeks or months of past conversations, across all your projects and machines. Past work becomes retrievable context instead of lost knowledge.

## Core value propositions

### 1. Decisions don't get re-litigated

When someone asks "why did we do it this way?", Total Recall finds the original conversation with the exact reasoning. No re-investigation, no guessing, no re-debating settled questions.

**Proof points:** TR-1, TR-2, TR-10

### 2. Bugs don't get re-investigated

If the same problem comes back, Total Recall finds the prior root-cause analysis. Skip the investigation and go straight to the fix.

**Proof points:** TR-3, TR-4

### 3. Sessions pick up where they left off

When a session runs out of context or you come back the next day, Total Recall loads what happened before. Seamless continuity across session boundaries.

**Proof points:** TR-6, TR-11

### 4. Knowledge compounds instead of evaporating

Every AI conversation adds to a searchable record. Interview frameworks, architecture decisions, debugging approaches, all of it stays findable months later.

**Proof points:** TR-5, TR-7, TR-8

### 5. Cloud sync extends reach across machines

With Contextify Cloud, Total Recall searches all your devices, not just the one you're sitting at. Work on a server via SSH, search from your Mac later.

**Proof points:** (cloud page section)

## What makes it different from search

Total Recall is not a search box. It's the AI itself retrieving context from past conversations as part of its current work. The user asks a question, the AI decides it needs historical context, and it goes and gets it. The retrieval happens inside the conversation flow, not as a separate step.

## How it works (technical)

Three components:
1. **contextify CLI** (`contextify search`, `contextify context`) - full-text search and entry retrieval against the local Contextify database
2. **`/total-recall` skill** - Claude Code skill that teaches the AI how to search effectively
3. **`contextify-researcher` agent** - specialized subagent that handles complex multi-query searches

The skill and agent are installed automatically when the CLI is set up. No configuration needed beyond installing Contextify.

## Headline candidates

- "Your AI remembers what happened last month"
- "Every past session becomes context for the current one"
- "Ask your AI what your AI said three weeks ago"
- "Cross-session memory for Claude Code and Codex"
- "The AI searches its own history so you don't re-solve problems"

## Target audiences

| Audience | What resonates |
|----------|---------------|
| Solo developer, multiple projects | Decision archaeology, session continuity |
| Team lead | Onboarding, knowledge preservation across team |
| Consultant, multiple clients | Cross-project search, keeping client contexts separate |
| Developer on multiple machines | Cloud sync extending reach |
