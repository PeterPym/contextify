# Provider Identity

Visual identity for third-party AI providers displayed in Contextify.

## Providers

| Provider | Directory | Color Token | Notes |
|----------|-----------|-------------|-------|
| Claude Code | `claude-code/` | `provider-claude` (#F97316) | Anthropic orange |
| Codex CLI | `codex-cli/` | `provider-codex` (#FFFFFF) | Requires shadow on light bg |

## Presentation Rules

### Template Rendering

All provider icons use template rendering mode, allowing color tinting:

```swift
Image(provider.iconImage)
    .renderingMode(.template)
    .foregroundStyle(providerColor)
```

### Shadow Requirement (Codex Only)

Codex CLI's white icon requires a shadow on light backgrounds for visibility:

**SwiftUI:**
```swift
.shadow(
    color: colorScheme == .light ? .black.opacity(0.7) : .clear,
    radius: 0.5
)
```

**CSS:**
```css
.codex-icon-light-bg {
    filter: drop-shadow(0 0 0.5px rgba(0, 0, 0, 0.7));
}
```

## App Implementation Reference

- Asset catalog: `Contextify/Contextify/Assets.xcassets/`
- Data model: `TimelineModels.swift:Provider`
- Rendering: `TimelineEntryRow.swift:113-124`

## Available Exports

Each provider has PNG exports at:
- 16px, 24px, 32px, 48px (common UI sizes)
- 1024px (high-res source)

SVG versions: TODO (not yet available)
