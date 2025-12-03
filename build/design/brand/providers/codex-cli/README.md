# Codex CLI Provider Identity

Visual identity for OpenAI's Codex CLI assistant.

## Brand Color

| Token | Hex | RGB |
|-------|-----|-----|
| `provider-codex` | #FFFFFF | 255, 255, 255 |

## Icon

- **Style:** Swirly brackets / code chevrons
- **Rendering:** Template mode with white tint
- **Shadow:** **REQUIRED** on light backgrounds

## Shadow Requirement

The white icon is invisible on light backgrounds. Always apply a shadow in light mode.

### SwiftUI

```swift
Image("codex-icon")
    .renderingMode(.template)
    .foregroundStyle(Color.providerCodex)  // white
    .shadow(
        color: colorScheme == .light ? .black.opacity(0.7) : .clear,
        radius: 0.5
    )
```

### CSS

```css
.codex-icon {
    color: var(--provider-codex);  /* #FFFFFF */
}

/* Light mode only */
@media (prefers-color-scheme: light) {
    .codex-icon {
        filter: drop-shadow(0 0 0.5px rgba(0, 0, 0, 0.7));
    }
}

/* Or with a class */
.codex-icon-light-bg {
    filter: drop-shadow(0 0 0.5px rgba(0, 0, 0, 0.7));
}
```

## Assets

```
exports/
├── codex-icon-16px.png
├── codex-icon-24px.png
├── codex-icon-32px.png
├── codex-icon-48px.png
└── codex-icon-1024px.png   # High-res source
```

## App Implementation

- Asset: `Contextify/Contextify/Assets.xcassets/codex-icon.imageset/`
- Model: `TimelineModels.swift:Provider.codexCLI`
- Shadow pattern used in 6+ views (see `build/docs/design/providers.md`)
