# Release Notes Guide

How to write user-facing release notes for Contextify.

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

## Examples

**Good:**
- "Fixed timeline badges getting stuck after processing"
- "Search results now highlight matching text"
- "Reduced memory usage when monitoring large projects"

**Bad:**
- "fix(timeline): clear QUEUED badge" (commit message, not user language)
- "Refactored orchestrator consolidation" (internal, no user impact)
- "Updated dependencies" (unless security-relevant)
