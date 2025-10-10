# Design Assets

This directory contains original, high-resolution design assets for the Contextify project.

## Purpose

- **Source of truth** for all visual assets
- **High-resolution originals** preserved for future resizing/regeneration
- **Version controlled** alongside code for consistency

## Directory Structure

```
design-assets/
├── README.md          # This file
└── icons/             # Application icons and UI symbols
    ├── claude-code-icon-1024px.png    # Claude Code provider icon (1024×1024)
    └── codex-icon-1024px.png          # Codex CLI provider icon (1024×1024)
```

## Asset Workflow

### Icons (icons/)

**Original Format:**
- Size: 1024×1024 px (high-resolution masters)
- Format: PNG with transparency
- Design: Zero-padding, icon fills canvas

**Derived Assets:**
Generated versions are placed in `Contextify/Contextify/Assets.xcassets/` for use in the app:
- @1x: 12-16px (1× scale)
- @2x: 24-32px (2× retina scale)
- @3x: 36-48px (3× super retina scale)

**Generation Process:**
1. Design/edit high-res version in `design-assets/icons/`
2. Resize to required scales (see `docs/assets/provider-icons.md` for specs)
3. Copy scaled versions to appropriate `.imageset/` in `Assets.xcassets/`
4. Xcode automatically generates `GeneratedAssetSymbols.swift`

## Adding New Assets

1. **Place originals here** in appropriate subdirectory
2. **Document specifications** in `docs/assets/`
3. **Generate scaled versions** for Xcode asset catalog
4. **Commit both** originals and generated assets

## Best Practices

- **Never edit generated assets directly** - always work from originals
- **Keep formats lossless** where possible (PNG, PDF)
- **Document design specs** (colors, dimensions, style guides)
- **Version control originals** to track design changes

---

Last updated: 2025-10-10
