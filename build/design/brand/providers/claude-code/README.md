# Claude Code Provider Identity

Visual identity for Anthropic's Claude Code AI assistant.

## Brand Color

| Token | Hex | RGB |
|-------|-----|-----|
| `provider-claude` | #D97757 | 217, 119, 87 |

## Icon

- **Style:** Orange asterisk mark
- **Rendering:** Template mode with color tint
- **Shadow:** Not required

## Presentation

```swift
Image("claude-code-icon")
    .renderingMode(.template)
    .foregroundStyle(Color.providerClaude)  // #D97757
```

```css
.claude-icon {
    color: var(--provider-claude);  /* #D97757 */
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
