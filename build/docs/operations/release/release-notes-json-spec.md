# Release Notes JSON Specification

**Status:** Planned (#P2-RELEASE-NOTES-JSON)
**Purpose:** Single-source release notes with automated multi-output generation.

## Overview

```
                    ┌─────────────────────────┐
                    │  git commits (app only) │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  LLM generates draft    │
                    │  (generate-release-     │
                    │   notes.sh)             │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  release-notes.json     │◄── Human edits
                    │  (single source)        │
                    └───────────┬─────────────┘
                                │
            ┌───────────────────┼───────────────────┐
            ▼                   ▼                   ▼
    ┌───────────────┐   ┌───────────────┐   ┌───────────────┐
    │ Sparkle HTML  │   │ CHANGELOG.md  │   │ App Store     │
    │ (website)     │   │ (public repo) │   │ "What's New"  │
    └───────────────┘   └───────────────┘   └───────────────┘
```

## JSON Schema

**Location:** `releases/vX.Y.Z/release-notes.json`

```json
{
  "$schema": "../schemas/release-notes.schema.json",
  "version": "1.0.1",
  "date": "2025-12-08",
  "channels": ["dmg"],
  "baseline": "v1.0.0",
  "summary": "First direct download release with bug fixes.",
  "sections": {
    "features": [
      {
        "text": "New feature description",
        "commits": ["abc1234"]
      }
    ],
    "improvements": [],
    "fixes": [
      {
        "text": "Fixed timeline badges getting stuck after processing",
        "commits": ["c008e01f"]
      },
      {
        "text": "Contact Support now uses correct email address",
        "commits": ["a18c2581"]
      }
    ]
  },
  "requirements": {
    "macos": "26.0",
    "chip": "Apple Silicon"
  },
  "generated_at": "2025-12-08T10:00:00Z",
  "generated_from": {
    "base_ref": "v1.0.0",
    "head_ref": "v1.0.1",
    "commit_count": 15
  }
}
```

## Output Formats

### 1. Sparkle HTML

**Output:** `website/release-notes/X.Y.Z.html`
**Template:** `releases/templates/release-notes.html.tmpl`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Contextify {{version}} Release Notes</title>
  <style>/* standard styles */</style>
</head>
<body>
  <h1>Contextify {{version}}</h1>
  <p>{{summary}}</p>

  {{#if sections.features}}
  <h2>New Features</h2>
  <ul>
    {{#each sections.features}}<li>{{text}}</li>{{/each}}
  </ul>
  {{/if}}

  {{#if sections.fixes}}
  <h2>Fixes</h2>
  <ul>
    {{#each sections.fixes}}<li>{{text}}</li>{{/each}}
  </ul>
  {{/if}}

  <h2>Requirements</h2>
  <ul>
    <li>macOS {{requirements.macos}} (Tahoe) or later</li>
    <li>{{requirements.chip}} (M1 or later)</li>
  </ul>
</body>
</html>
```

### 2. CHANGELOG.md Entry

**Output:** Prepended to `~/code/projects/contextify-public-repo/CHANGELOG.md`

```markdown
## [{{version}}] - {{date}}

{{summary}}

{{#if sections.features}}
### New Features
{{#each sections.features}}
- {{text}}
{{/each}}
{{/if}}

{{#if sections.fixes}}
### Fixes
{{#each sections.fixes}}
- {{text}}
{{/each}}
{{/if}}
```

### 3. App Store "What's New"

**Output:** `releases/vX.Y.Z/appstore-whats-new.txt`
**Constraints:** 4000 character limit, plain text

```
{{summary}}

{{#if sections.features}}
New Features:
{{#each sections.features}}
• {{text}}
{{/each}}
{{/if}}

{{#if sections.fixes}}
Fixes:
{{#each sections.fixes}}
• {{text}}
{{/each}}
{{/if}}
```

## Workflow

### Step 1: Generate Draft

```bash
./scripts/release/generate-release-notes.sh X.Y.Z --from vPREVIOUS --json
```

Creates `releases/vX.Y.Z/release-notes.json` with LLM-drafted content.

### Step 2: Human Review

Edit `releases/vX.Y.Z/release-notes.json`:
- Verify user-facing language (not commit speak)
- Remove internal/non-user-facing changes
- Group related items
- Polish summary

### Step 3: Generate Outputs

```bash
./scripts/release/render-release-notes.sh X.Y.Z
```

Generates all three outputs from JSON source.

### Step 4: Deploy

```bash
# Website (Sparkle)
./scripts/deploy-website.sh

# Public repo CHANGELOG
cd ~/code/projects/contextify-public-repo
git add CHANGELOG.md && git commit -m "docs: add X.Y.Z release notes" && git push

# App Store (manual paste into App Store Connect)
cat releases/vX.Y.Z/appstore-whats-new.txt | pbcopy
```

## Scripts to Create

| Script | Purpose |
|--------|---------|
| `scripts/release/generate-release-notes.sh` | LLM draft from commits (exists, add --json flag) |
| `scripts/release/render-release-notes.sh` | JSON → HTML/MD/TXT outputs |
| `scripts/release/validate-release-notes.sh` | Schema validation |

## Integration Points

### Release Workflow

Update `releases/WORKFLOW.md` Phase 5 (Marketing) to use JSON workflow:

1. Generate JSON draft
2. Human review/edit
3. Render outputs
4. Deploy

### PUBLIC-SURFACES.md

Add JSON source to inventory:
- Source: `releases/vX.Y.Z/release-notes.json`
- Outputs: HTML (Sparkle), CHANGELOG (public repo), TXT (App Store)

### Checklist Templates

Update `releases/templates/checklists/05-marketing.md`:
- [ ] Generate release notes JSON: `./scripts/release/generate-release-notes.sh X.Y.Z --json`
- [ ] Review and edit: `releases/vX.Y.Z/release-notes.json`
- [ ] Render outputs: `./scripts/release/render-release-notes.sh X.Y.Z`
- [ ] Deploy website
- [ ] Update public repo CHANGELOG
- [ ] Copy App Store text to Connect

## Migration

For existing releases (1.0.0, 1.0.1), backfill JSON from existing HTML if needed for CHANGELOG generation.
