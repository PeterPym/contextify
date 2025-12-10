# Contextify Asset Catalog

Central index of all visual assets for AI agents and humans. Use this to find the right asset for any context.

## Quick Reference

| Need | Location | Key Files |
|------|----------|-----------|
| App Store screenshots | `appstore-metadata/screenshots/final/` | `01-main-hud-*.png`, `02-dual-provider-*.png` |
| Website images | `website/assets/img/` | `contextify-screenshot-{dark,light}.png` |
| Social/promo shots | `build/assets/screenshots/` | Feature-specific screenshots |
| Brand colors | `build/design/brand/colors.md` | Color tokens, hex values |
| App icon | `build/design/brand/logomark/` | Source files |
| OG/social preview | `website/assets/img/og-banner.png` | 1200x630 social card |

---

## Asset Inventory

### App Store Screenshots
**Location:** `appstore-metadata/screenshots/final/`
**Format:** PNG, 2880x1800 (Retina)
**Use:** App Store listing, formal marketing

| File | Shows | Keywords | Version |
|------|-------|----------|---------|
| `01-main-hud-*-with-text.png` | Main timeline HUD with conversation | timeline, main view, dark mode, conversation | v1.0.0 |
| `02-dual-provider-*-with-text.png` | Claude Code + Codex side by side | dual provider, codex, claude code, comparison | v1.0.0 |
| `03-transcript-inventory-*-with-text.png` | Transcript list/browser | transcript list, inventory, browse | v1.0.0 |
| `05-settings-*-with-text.png` | Settings panel | settings, preferences, configuration | v1.0.0 |

**No-title variants:** `final/no-titles/` - same shots without marketing text overlay

---

### Website Images
**Location:** `website/assets/img/`
**Use:** contextify.sh website, landing page

| File | Shows | Keywords | Version | Notes |
|------|-------|----------|---------|-------|
| `contextify-screenshot-dark.png` | Main app (dark theme) | hero, main, dark mode | v1.0.0 | Primary hero image |
| `contextify-screenshot-light.png` | Main app (light theme) | hero, main, light mode | v1.0.0 | Alt hero |
| `feature-search-cropped.png` | Search window | search, find, query | v1.0.0 | Feature highlight |
| `feature-sync-cropped.png` | Real-time sync indicator | sync, monitoring, real-time | v1.0.0 | Feature highlight |
| `feature-timeline-cropped.png` | Timeline view | timeline, conversation, history | v1.0.0 | Feature highlight |
| `og-banner.png` | Social preview card | og, social, twitter, facebook | v1.0.0 | 1200x630, needs update |
| `apple-intelligence-macos-tahoe.png` | Apple Intelligence badge | apple intelligence, AI, local | n/a | Tahoe requirement callout |
| `contextify-icon.png` | App icon (small) | icon, logo | v1.0.0 | 512px |

**WebP variants:** Most PNGs have `.webp` versions for web performance.

---

### Promotional Screenshots
**Location:** `build/assets/screenshots/`
**Use:** Reddit, Twitter, blog posts, docs, feature explanations

| File | Shows | Keywords | Version | Best For |
|------|-------|----------|---------|----------|
| `queued-message-claude-code-dark.png` | Queued message indicator | queue, message, status, dark | v1.0.2 | Explaining queue feature |
| `queued-message-claude-code-light.png` | Queued message (light) | queue, message, light | v1.0.2 | Light mode contexts |
| `queued-message-claude-code-summarized-dark.png` | Queue + AI summary | queue, summary, apple intelligence | v1.0.2 | Showing LLM integration |

---

### Brand Assets

#### Colors
**Location:** `build/design/brand/colors.md`
**Keywords:** color, palette, theme, hex, brand

Key colors:
- Primary: Indigo (`#6366F1`)
- Background dark: Slate 900 (`#0F172A`)
- Background light: White (`#FFFFFF`)
- See `colors.md` for full Slate scale and semantic tokens

#### App Icon
**Location:** `build/design/brand/logomark/`
**Keywords:** icon, logo, app icon

#### Store Badges
**Location:** `build/design/brand/app-store-badges/`
**Also:** `website/assets/img/mac-app-store-badge.svg`
**Keywords:** app store, badge, download, mac app store

---

### Video Assets

| Asset | URL | Duration | Keywords |
|-------|-----|----------|----------|
| Demo video | https://www.youtube.com/watch?v=FvrvRGp4C9M | 3:39 | demo, walkthrough, features |
| YouTube channel | https://www.youtube.com/@contextify_sh | - | channel, youtube |

---

## Asset Selection Guide

**For Reddit/social posts:**
- Use `build/assets/screenshots/` for feature callouts
- Use `website/assets/img/contextify-screenshot-dark.png` for general hero shot

**For App Store:**
- Only use `appstore-metadata/screenshots/final/` (meets size requirements)

**For website:**
- Use `website/assets/img/` (optimized, has WebP variants)

**For documentation:**
- Prefer `build/assets/screenshots/` for feature-specific shots
- Can use website assets for general shots

**For social cards/OG:**
- `website/assets/img/og-banner.png` (needs update - see TODOS.md)

---

## Adding New Assets

1. **Determine category:** App Store, website, promotional, or brand
2. **Use naming convention:** `contextify-{type}-{feature}-{variant}-{theme}.png`
3. **Place in correct directory:**
   - App Store: `appstore-metadata/screenshots/drafts/` → review → `final/`
   - Website: `website/assets/img/` (add WebP variant)
   - Promo/general: `build/assets/screenshots/`
4. **Update this catalog** with file, description, and keywords
5. **For website:** Run optimization to generate WebP

---

## Related Documentation

- `build/design/README.md` - Design system overview
- `build/design/brand/colors.md` - Color tokens
- `appstore-metadata/README.md` - App Store metadata guide
- `appstore-metadata/screenshots/SCREENSHOT-SPECIFICATIONS.md` - App Store screenshot specs
