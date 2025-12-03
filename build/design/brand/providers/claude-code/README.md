# Claude Code Provider Identity

Visual identity for Anthropic's Claude Code AI assistant.

## Brand Color

| Token | Hex | RGB |
|-------|-----|-----|
| `provider-claude` | #F97316 | 249, 115, 22 |

## Icon

- **Style:** Orange asterisk mark
- **Rendering:** Template mode with color tint
- **Shadow:** Not required

## Presentation

```swift
Image("claude-code-icon")
    .renderingMode(.template)
    .foregroundStyle(Color.providerClaude)  // #F97316
```

```css
.claude-icon {
    color: var(--provider-claude);  /* #F97316 */
}
```

## Assets

```
exports/
├── claude-code-icon-16px.png
├── claude-code-icon-24px.png
├── claude-code-icon-32px.png
├── claude-code-icon-48px.png
└── claude-code-icon-1024px.png   # High-res source
```

## App Implementation

- Asset: `Contextify/Contextify/Assets.xcassets/claude-code-icon.imageset/`
- Model: `TimelineModels.swift:Provider.claudeCode`
