# Contextify Origin Story

Raw material for Show HN, website copy, interviews, etc.

---

## The FileKitty Era

Before Claude Code, I was doing AI-assisted programming through web-based chat interfaces like ChatGPT. I built an open source tool called **FileKitty** that let you rapidly select, combine, and copy contents of files. Paired with the right prompts, you could get outstanding results even from what are now historical versions of frontier models.

FileKitty made the front page of Hacker News when I shared the first version.

This was context curation, or "context engineering," before these were common terms.

---

## The Claude Code Shift (June 2024)

In June I got exposure to Claude Code and it quickly became the dominant modality for AI-assisted programming.

Back in web-based AI work, I would regularly use ChatGPT's sidebar to search for things I'd explored in prior conversations. Search is still kind of rough in ChatGPT, but it does work.

Two things concerned me about Claude Code:

1. **No searchable history** - Discussions aren't retained by Anthropic in a way accessible to users
2. **Auto-deletion** - By default, past conversations are automatically deleted off your local machine after 30 days

Thanks to FileKitty, I'd been thinking about context preservation before it was trendy. It bothered me that this important history was being swept under the rug.

---

## The Multi-Tool Problem (Late August 2024)

OpenAI's Codex CLI emerged as competition to Claude Code. I would find myself burning through my weekly subscription limits on Claude Code, then switching to Codex.

This created a familiar problem from my web chat days: solving big problems across both services, then struggling to piece together a past session that had been split between them.

The silver lining: Codex and Claude Code use a similar local data storage format for their chat histories. This meant a unified tool was possible.

---

## What Contextify Does

Contextify watches both Claude Code and Codex, summarizes conversations in real-time with LLM-generated summaries, and keeps everything in one searchable database.

It's a native macOS app that sits in the corner as a HUD, showing you a live timeline of your current session. The full history is searchable across all your projects.

---

## Key Themes

- **Context engineering before the term existed** - FileKitty was about curating context for AI; Contextify is about preserving it
- **Your work history matters** - 30-day auto-deletion is the wrong default
- **Tool-agnostic preservation** - Work across Claude Code, Codex, whatever comes next
- **Local-first** - Your data stays on your machine, searchable by you
