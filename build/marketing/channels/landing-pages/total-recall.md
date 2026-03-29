# Landing Page Brief: /total-recall/

**Target URL:** contextify.sh/total-recall/
**Bloon task:** ct-669
**Status:** Not yet built

## Purpose

Dedicated product page for Total Recall. The cloud page has a section on it, but Total Recall works locally too and deserves its own page.

## Audience

Primary: developers using Claude Code or Codex who have been using AI coding assistants for weeks/months and have lost track of past conversations.

## Page Structure (proposed)

### 1. Hero
- Headline: (pick from value-props.md candidates, or iterate)
- Subhead: Your Claude Code and Codex sessions can search every past session. Decisions, code patterns, and solutions become retrievable context.
- Terminal mockup showing a `/total-recall` query and result (similar to cloud page hero)

### 2. The Problem
- AI conversations are ephemeral. Claude Code deletes after 30 days. Even if they're still on disk, you can't search across them. You end up re-solving the same problems.

### 3. How It Works
- Three components: CLI tool, skill, researcher agent
- Installed automatically with Contextify
- The AI decides when to search, you don't have to remember to look things up

### 4. Real Examples (proof points)
- Use top 5-6 from proof-points.md (TR-1 through TR-6)
- Format: user question, what Total Recall found, outcome
- Group by pattern: Decision archaeology, Bug forensics, Session continuity

### 5. With Cloud Sync
- Brief callout: cloud sync extends reach across all your machines
- Link to /cloud/ page

### 6. Setup
- DMG: Settings > CLI > Install
- App Store: Homebrew tap
- Linux: included with CLI package
- "Restart Claude Code, skill registers automatically"

### 7. CTA
- Download Contextify
- See Pricing (for cloud plans)

## Content Sources

- `content/products/total-recall/proof-points.md` - proof point IDs TR-1 through TR-12
- `content/products/total-recall/value-props.md` - value propositions and headlines
- `content/products/total-recall/use-cases.md` - use case taxonomy
- `content/products/total-recall/case-studies.md` - (pending, from usage analysis)
- Blog post: `website/blog/total-recall-rag-search-claude-code-codex.html` - setup instructions
- Cloud page section: `website/cloud/index.html` (Total Recall section)

## Design Notes

- Match site design: Bootstrap 5.3, CSS tokens from styles.css, dark mode, nav/footer pattern
- See cloud page for reference implementation of similar product page
- Terminal mockups should use the same `.terminal-block` styles
