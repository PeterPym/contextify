# Release Notes Guide

How to write user-facing release notes for Contextify.

## Release History & Baselines

| Version | Channels | Baseline | Notes |
|---------|----------|----------|-------|
| 1.0.0 | App Store only | - | Initial public release |
| 1.0.1 | DMG only | v1.0.0 | First DMG/Sparkle release, bug fixes |

**Baseline:** The version to diff against for "what's new".

For 1.0.1 DMG release:
```bash
git log --oneline v1.0.0..v1.0.1 -- app/ Contextify/
```

Check `releases/manifest.json` for channel status and git tags.

## Future: JSON-based Release Notes

**Status:** Planned (see #P2-RELEASE-NOTES-JSON in TODOS.md)

Single-source JSON at `releases/vX.Y.Z/release-notes.json`:

```json
{
  "version": "1.0.1",
  "date": "2025-12-08",
  "channels": ["dmg"],
  "baseline": "v1.0.0",
  "summary": "First direct download release with bug fixes.",
  "sections": {
    "features": [],
    "improvements": [],
    "fixes": [
      "Fixed timeline badges getting stuck after processing",
      "Contact Support now uses correct email address"
    ]
  }
}
```

Generate outputs:
- `website/release-notes/X.Y.Z.html` (Sparkle in-app dialog)
- Public repo `CHANGELOG.md` entry
- App Store "What's New" text

## File Locations

| File | Purpose |
|------|---------|
| `website/release-notes/X.Y.Z.html` | Sparkle in-app update dialog (HTML) |
| `CHANGELOG.md` | Full changelog in repo |
| `releases/vX.Y.Z/assets/changelog.llm.md` | LLM-generated draft |
| `releases/vX.Y.Z/assets/changelog.final.md` | Edited final version |

## Generating Release Notes

### Step 1: Get app-only commits

```bash
# See what changed since last version
git log --oneline vPREVIOUS..HEAD -- app/ Contextify/
```

### Step 2: Generate LLM draft (optional)

```bash
./scripts/release/generate-release-notes.sh X.Y.Z --from vPREVIOUS
```

This scopes to `releases/config/app-paths.txt` and outputs to `releases/vX.Y.Z/assets/changelog.llm.md`.

### Step 3: Write user-facing notes

**Focus on user impact, not implementation:**

| Commit Message | User-Facing Note |
|----------------|------------------|
| `fix(timeline): clear QUEUED badge and pulsing hourglass after state changes` | Fixed timeline badges getting stuck after processing |
| `fix(database): use Application Support for DMG builds` | DMG version no longer prompts for folder access on first launch |
| `refactor(orchestrator): consolidate project activation` | (skip - internal refactor, no user impact) |

**Guidelines:**
- Lead with the benefit, not the fix
- Skip internal refactors, test-only changes, docs
- Group related fixes together
- Keep it scannable (bullet points)

### Step 4: Create HTML for Sparkle

Create `website/release-notes/X.Y.Z.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Contextify X.Y.Z Release Notes</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
      line-height: 1.6;
      color: #333;
    }
    h1 { font-size: 1.5em; margin-bottom: 0.5em; }
    h2 { font-size: 1.2em; margin-top: 1.5em; margin-bottom: 0.5em; color: #555; }
    ul { margin: 0; padding-left: 1.5em; }
    li { margin-bottom: 0.5em; }
  </style>
</head>
<body>
  <h1>Contextify X.Y.Z</h1>
  <p>Brief summary of release focus.</p>

  <h2>New Features</h2>
  <ul>
    <li>Feature description</li>
  </ul>

  <h2>Fixes</h2>
  <ul>
    <li>Bug fix description</li>
  </ul>

  <h2>Requirements</h2>
  <ul>
    <li>macOS 26.0 (Tahoe) or later</li>
    <li>Apple Silicon (M1 or later)</li>
  </ul>
</body>
</html>
```

### Step 5: Update appcast.xml

Point to the release notes:

```xml
<sparkle:releaseNotesLink>
  https://contextify.sh/release-notes/X.Y.Z.html
</sparkle:releaseNotesLink>
```

### Step 6: Deploy

```bash
./scripts/deploy-website.sh
```

## Categories

Use these sections as needed:

- **New Features** - New capabilities
- **Improvements** - Enhanced existing features
- **Fixes** - Bug fixes
- **Requirements** - System requirements (always include)

Skip empty sections.

## Writing Style: Lessons from v1.1.0

These guidelines emerged from the v1.1.0 release notes iteration.

### Structure: Scannable First, Details Later

Users skim. Put the highlights at the top as a bullet list, then expand below.

**Good structure:**
```
What's New in v1.1.0

• Feature A - One-line summary.
• Feature B - One-line summary.
• Feature C - One-line summary.

Feature A Details (if needed)

Expanded explanation for users who want more context...
```

**Bad structure:**
```
What's New in v1.1.0

Feature A

Three paragraphs about Feature A before the user even knows
what else is in the release...
```

### Channel Awareness: Only Include What's Relevant

**App Store users don't care about:**
- Linux CLI support
- DMG-only features (automatic worktree grouping)
- Build system changes

**DMG users don't care about:**
- Sandbox permission changes
- App Store review accommodations

When writing notes, ask: "Does this channel's user see/use this feature?"

### Feature Framing: Benefits, Not Mechanics

| Bad (Technical) | Good (User Benefit) |
|-----------------|---------------------|
| "Fixed project attribution for cross-directory sessions" | "Git worktree recognition - search across all related projects" |
| "Added MarkdownUI dependency" | "Markdown tables now render nicely in details" |
| "Improved accuracy" (vague) | Describe what's actually improved |

### Context for CLI/External Features

Features requiring external installation need context:

**Bad:**
```
• Codex CLI Support - Works with Codex.
```

**Good:**
```
Total Recall Improvements (install via Settings > CLI)

Total Recall is a skill for Claude Code and Codex. It tells your
AI how to use contextify-query, a CLI interface to your complete
conversational history.

• Codex CLI Support - Total Recall now works with OpenAI's Codex
  CLI alongside Claude Code.
```

### Avoid Robotic Bullet Points

If every bullet follows the same pattern, the notes feel mechanical.

**Robotic:**
```
• Feature A - Description of A.
• Feature B - Description of B.
• Feature C - Description of C.
```

**Natural:**
```
• Feature A - Description that flows naturally.
• Feature B - This one can be longer when the feature
  warrants it, with an example or use case.
• Feature C - Brief.
```

### Common Mistakes

1. **Missing features entirely** - Cross-reference the internal changelog against the external notes
2. **Including irrelevant channels** - Linux support in App Store notes
3. **Vague improvements** - "Improved accuracy" without saying what improved
4. **No installation context** - CLI features need "install via Settings > CLI"
5. **Description not updated** - App Store description should evolve with major features

## Examples

**Good:**
- "Fixed timeline badges getting stuck after processing"
- "Search results now highlight matching text"
- "Reduced memory usage when monitoring large projects"

**Bad:**
- "fix(timeline): clear QUEUED badge" (commit message, not user language)
- "Refactored orchestrator consolidation" (internal, no user impact)
- "Updated dependencies" (unless security-relevant)
