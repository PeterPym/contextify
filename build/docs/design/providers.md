# Provider Iconography

Visual identity for AI providers displayed in Contextify.

## Provider Logomarks

Contextify displays provider-specific logomarks for assistant messages. **Never use generic icons (e.g., sparkles) for assistant content** - always use the appropriate provider logomark.

### Claude Code

| Property | Value |
|----------|-------|
| Asset | `claude-code-icon` |
| Color | `.orange` |
| Description | Orange asterisk mark |

### Codex CLI

| Property | Value |
|----------|-------|
| Asset | `codex-icon` |
| Color | `.white` (template rendering) |
| Description | Blue swirly brackets mark |

**Light mode requirement:** Codex icon requires a shadow in light mode for visibility against light backgrounds:

```swift
.shadow(
    color: (colorScheme == .light && provider == .codexCLI) ? .black.opacity(0.7) : .clear,
    radius: 0.5
)
```

## Assets

Located in `Contextify/Contextify/Assets.xcassets/`:

```
claude-code-icon.imageset/
├── claude-code-icon@1x.png
├── claude-code-icon@2x.png
├── claude-code-icon@3x.png
└── Contents.json

codex-icon.imageset/
├── codex-icon@1x.png
├── codex-icon@2x.png
├── codex-icon@3x.png
└── Contents.json
```

## Implementation

### Data Model

Provider information is available via `TimelineSourceContext.Provider` enum in `TimelineModels.swift`:

```swift
public enum Provider: String, Sendable {
    case claudeCode = "claude.code"
    case codexCLI = "codex.cli"
    case other

    var iconImage: String {
        switch self {
        case .claudeCode: return "claude-code-icon"
        case .codexCLI:   return "codex-icon"
        case .other:      return "sparkles"  // Fallback only - avoid reaching this
        }
    }

    var color: Color {
        switch self {
        case .claudeCode: return .orange
        case .codexCLI:   return .white
        case .other:      return .gray
        }
    }
}
```

### Reference Implementation

See `TimelineEntryRow.swift:112-124` for the canonical pattern:

```swift
if entry.kind == .assistant, let provider = entry.sourceContext?.provider {
    Image(provider.iconImage)
        .renderingMode(.template)
        .foregroundStyle(providerColor(provider))
        .shadow(
            color: (colorScheme == .light && provider == .codexCLI) ? .black.opacity(0.7) : .clear,
            radius: 0.5
        )
} else {
    Image(systemName: entry.kind.iconName)
        .foregroundStyle(entry.kind.accentColor)
}
```

**Key points:**
- Use `.renderingMode(.template)` to allow color tinting
- Apply provider-specific color via `.foregroundStyle()`
- Add shadow for Codex in light mode
- Fallback to system icon only when provider is unavailable (should be rare)

## Usage Guidelines

1. **Always prefer provider logomarks** over generic icons for assistant messages
2. **Check for provider availability** via `entry.sourceContext?.provider`
3. **Apply the light mode shadow** for Codex to ensure visibility
4. **Use template rendering** to allow the icon to adapt to the provider color

## Where to Apply

Provider logomarks should appear wherever assistant messages are displayed:
- Timeline entries (`TimelineEntryRow`)
- Search results (`SearchHitRow`, `DeepSearchHitRow`)
- Context panes (`ContextEntryRow`)
- Any future views showing assistant content
