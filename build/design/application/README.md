# Application Design

Design documentation for the Contextify macOS app.

## Directory Structure

```
application/
├── README.md           # This file
└── icon/               # App icon (Icon Composer project)
    ├── README.md
    ├── HISTORY.md
    └── icon-composer-project.icon -> Contextify/...
```

## App Icon

The macOS app icon uses the logomark (`build/design/brand/logomark/`) composed via Apple's Icon Composer with platform-specific treatments (glass, shadows, sizing).

See `icon/README.md` for details.

## App UI Design

In-app UI patterns (colors, SwiftUI patterns, components) are documented in:
- `build/docs/design/color-scheme.md` - App UI colors (blue/green/taupe)
- `build/docs/design/providers.md` - Provider iconography
- `build/docs/design/swiftui-patterns.md` - SwiftUI architecture patterns

**Note:** App UI colors (blue/green/taupe) are distinct from brand colors (yellow/cyan/purple). See `build/design/README.md` for the distinction.

## TODO

- [ ] Consider moving `build/docs/design/` content here for consolidation
- [ ] Document component library (buttons, cards, etc.)
- [ ] Document spacing/layout system
