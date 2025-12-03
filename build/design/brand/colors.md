# Contextify Color Tokens

Canonical color definitions for the Contextify design system. All implementations (Swift, CSS) should reference these values.

## Token Naming Convention

| Aspect | Convention |
|--------|------------|
| **Namespace** | `contextify-` prefix for our colors |
| **CSS** | kebab-case (`--contextify-primary`) |
| **Swift** | camelCase (`contextifyPrimary`) |
| **Provider colors** | `provider-` prefix (third-party identity) |
| **Format** | Hex values as source of truth |

---

## Semantic Colors

Application UI colors with semantic meaning.

| Token | Hex | Usage |
|-------|-----|-------|
| `contextify-primary` | #4A7BA7 | User actions, links, interactive elements |
| `contextify-secondary` | #9B8B7E | Assistant content, neutral UI |
| `contextify-success` | #51A86B | Completion, success states |
| `contextify-warning` | #D4A84E | Warnings, pending states |
| `contextify-error` | #C74E4E | Errors, destructive actions |
| `contextify-accent` | #7C68A8 | Metadata, generated content |

---

## Brand Colors

Colors from the Contextify logomark gradient.

| Token | Hex | Position |
|-------|-----|----------|
| `contextify-brand-yellow` | #F9B233 | Left loop (approximate) |
| `contextify-brand-cyan` | #4AC4E0 | Center crossing (approximate) |
| `contextify-brand-purple` | #8B5CF6 | Right loop (approximate) |

**Note:** These are approximations. TODO: Extract exact values from logomark PNG.

---

## Provider Colors

Third-party brand colors for AI providers. These are not Contextify colors - they represent external brand identity.

| Token | Hex | Provider | Notes |
|-------|-----|----------|-------|
| `provider-claude` | #D97757 | Claude Code | Anthropic coral |
| `provider-codex` | #FFFFFF | Codex CLI | Requires shadow on light backgrounds |

See `providers/` for presentation rules and assets.

---

## Implementation

### CSS

```css
:root {
  /* Semantic */
  --contextify-primary: #4A7BA7;
  --contextify-secondary: #9B8B7E;
  --contextify-success: #51A86B;
  --contextify-warning: #D4A84E;
  --contextify-error: #C74E4E;
  --contextify-accent: #7C68A8;

  /* Brand */
  --contextify-brand-yellow: #F9B233;
  --contextify-brand-cyan: #4AC4E0;
  --contextify-brand-purple: #8B5CF6;

  /* Provider (third-party) */
  --provider-claude: #D97757;
  --provider-codex: #FFFFFF;
}
```

### Swift

```swift
extension Color {
    // Semantic
    static let contextifyPrimary = Color(red: 0.290, green: 0.482, blue: 0.655)    // #4A7BA7
    static let contextifySecondary = Color(red: 0.608, green: 0.545, blue: 0.494)  // #9B8B7E
    static let contextifySuccess = Color(red: 0.318, green: 0.659, blue: 0.420)    // #51A86B
    static let contextifyWarning = Color(red: 0.831, green: 0.659, blue: 0.306)    // #D4A84E
    static let contextifyError = Color(red: 0.780, green: 0.306, blue: 0.306)      // #C74E4E
    static let contextifyAccent = Color(red: 0.486, green: 0.408, blue: 0.659)     // #7C68A8

    // Brand
    static let contextifyBrandYellow = Color(red: 0.976, green: 0.698, blue: 0.200) // #F9B233
    static let contextifyBrandCyan = Color(red: 0.290, green: 0.769, blue: 0.878)   // #4AC4E0
    static let contextifyBrandPurple = Color(red: 0.545, green: 0.361, blue: 0.965) // #8B5CF6

    // Provider (third-party)
    static let providerClaude = Color(red: 0.851, green: 0.467, blue: 0.341)       // #D97757
    static let providerCodex = Color.white                                          // #FFFFFF
}
```

---

## Migration Notes

### Current Swift (SharedExtensions.swift)

The existing code uses slightly different names:

| Current | New Token |
|---------|-----------|
| `contextifyBlue` | `contextify-primary` |
| `contextifyTaupe` | `contextify-secondary` |
| `contextifyGreen` | `contextify-success` |
| `contextifyYellow` | `contextify-warning` |
| `contextifyRed` | `contextify-error` |
| `contextifyPurple` | `contextify-accent` |

Migration to new names is a future task. Current code continues to work.

### Current Website (styles.css)

Website uses a legacy palette from ChiefOfStaff/INSPINIA. Migration to these tokens is part of the website redesign.
