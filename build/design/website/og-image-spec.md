# OG Image Specification

**File:** `website/assets/img/og-banner.png`
**Dimensions:** 1200x630 (standard OG image)

## Current State (needs update)

- Generic tagline: "AI Session Monitoring for macOS"
- Byline text too small to read at thumbnail sizes
- Doesn't convey the core value prop

## New Design Requirements

### Copy (top to bottom)

**Line 1 (headline - large):**
> Your Claude Code history deletes after 30 days.

**Line 2 (headline - large):**
> Contextify keeps it forever.

**Line 3 (tagline - medium, below logo):**
> Real-time AI session monitoring and total recall for Claude Code and Codex

### Visual Hierarchy

1. The two headline lines should be the dominant text - readable even at small thumbnail sizes
2. Logo centered
3. Tagline below logo, medium size (not tiny like current)
4. Background: use brand slate colors (see `build/design/brand/colors.md`)

### Size Guidelines

- Headlines: Large enough to read in a Twitter card preview (~200px wide)
- Tagline: At least 24px equivalent - current is too small
- Test at 600x315 (half size) to ensure readability

### Brand Assets

- Logo: `website/assets/img/contextify-icon.png`
- Colors: See `build/design/brand/colors.md` (Slate scale)
- Current background: `#3d4654` (Slate 700ish)

## Testing

After generating, validate with:
- Twitter Card Validator: https://cards-dev.twitter.com/validator
- LinkedIn Post Inspector: https://www.linkedin.com/post-inspector/
- Facebook Sharing Debugger: https://developers.facebook.com/tools/debug/

## Deployment

1. Replace `website/assets/img/og-banner.png`
2. Deploy website: `./scripts/deploy-website.sh`
3. Clear social media caches (validators above will refresh)
