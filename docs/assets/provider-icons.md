# Provider Icons for Timeline

This document describes the custom icon assets needed for the conversation timeline provider indicators.

## Icon Specifications

### File Format
- **Preferred:** PDF (vector format, resolution-independent)
- **Alternative:** PNG with @1x, @2x, @3x variants

### Dimensions
- **Base size:** 16×16 pt (template size)
- **Canvas:** 20×20 pt with 2pt padding (matches SF Symbol spacing)
- **PNG sizes (if not using PDF):**
  - @1x: 16×16 px
  - @2x: 32×32 px
  - @3x: 48×48 px

### Design Guidelines
- **Style:** Simple, iconic, monochrome (single color)
- **Stroke weight:** 1.5-2pt (match SF Symbol Regular weight)
- **Color handling:** Template rendering mode (tinted programmatically)
- **Alignment:** Optically centered in 20×20 canvas

## Required Icons

### 1. Claude Code Icon
- **Asset name:** `claude-code-icon`
- **Design:** Orange asterisk or stylized "C" mark
- **Reference color:** Orange (#FF9500) - applied programmatically
- **Character:** Bold, confident, friendly
- **Inspiration:** Claude Code's orange branding

### 2. Codex Icon
- **Asset name:** `codex-icon`
- **Design:** Swirly brackets or code chevrons `</>`
- **Reference color:** Blue (#007AFF) - applied programmatically
- **Character:** Technical, precise, clean
- **Inspiration:** OpenAI Codex branding

## Asset Location

Add to Xcode Asset Catalog:
```
Contextify/Assets.xcassets/
├── claude-code-icon.imageset/
│   ├── Contents.json
│   └── claude-code-icon.pdf (or .png variants)
└── codex-icon.imageset/
    ├── Contents.json
    └── codex-icon.pdf (or .png variants)
```

## Implementation Notes

The icons are already integrated in the codebase:
- `TimelineModels.swift`: Provider extension with `iconImage` property
- `TimelineEntryRow.swift`: Renders provider icon to left of timestamp
- Template rendering with programmatic color tinting

**Current fallback:** Emoji placeholders (🟠/🌀) used until custom assets are added.

## Example SF Symbol Reference

For design consistency, reference these SF Symbols:
- `terminal.fill` - Current Claude Code icon in inventory
- `chevron.left.forwardslash.chevron.right` - Current Codex icon in inventory
- Size and weight should match these symbols

## Testing

After adding the assets:
1. Build the app
2. View system messages in timeline
3. Verify icons appear to left of timestamp
4. Check color tinting (orange for Claude Code, blue for Codex)
5. Test in both light and dark mode

---

Last updated: 2025-10-10
