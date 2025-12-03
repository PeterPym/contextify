# Contextify Color System

Canonical color definitions for the Contextify design system. Single source of truth for website and macOS app.

**Last Updated:** 2024-12

---

## Token Naming

| Aspect | Convention |
|--------|------------|
| **CSS** | kebab-case with prefix (`--contextify-primary`, `--slate-500`) |
| **Swift** | camelCase (`contextifyPrimary`, `slate500`) |
| **Semantic** | `contextify-` prefix |
| **Neutrals** | `slate-` prefix (Tailwind scale) |
| **Provider** | `provider-` prefix (third-party) |

---

## 1. Semantic Colors

Purpose-driven colors for UI meaning.

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `primary` | #4A7BA7 | #6A9BC7 | Actions, links, interactive elements |
| `secondary` | #9B8B7E | #B5A89D | Assistant content, neutral emphasis |
| `success` | #51A86B | #6BC885 | Completion, positive states |
| `warning` | #D4A84E | #E4B85E | Caution, pending states |
| `error` | #C74E4E | #D76E6E | Errors, destructive actions |
| `info` | #4A7BA7 | #6A9BC7 | Informational (aliases primary) |
| `accent` | #7C68A8 | #9C88C8 | Metadata, generated content |

### Semantic Variants

Each semantic color has derived variants:

| Variant | Purpose | Derivation |
|---------|---------|------------|
| `{color}` | Base color | As defined above |
| `{color}-hover` | Hover state | Darken 10% (light) / Lighten 10% (dark) |
| `{color}-light` | Background tint | 10% opacity on white (light) / 15% opacity on dark bg (dark) |

**Light mode variants:**

| Token | Hex | Derivation |
|-------|-----|------------|
| `primary-hover` | #3D6A94 | primary darkened |
| `primary-light` | #E8F0F7 | primary @ 10% on white |
| `success-light` | #E8F5EC | success @ 10% on white |
| `warning-light` | #FDF6E8 | warning @ 10% on white |
| `error-light` | #FBEAEA | error @ 10% on white |
| `info-light` | #E8F0F7 | info @ 10% on white |

**Dark mode variants:**

| Token | Hex | Derivation |
|-------|-----|------------|
| `primary-hover` | #7AABDA | primary lightened |
| `primary-light` | #1E3A52 | primary @ 15% on slate-900 |
| `success-light` | #1A3028 | success @ 15% on slate-900 |
| `warning-light` | #3A3020 | warning @ 15% on slate-900 |
| `error-light` | #3A2020 | error @ 15% on slate-900 |
| `info-light` | #1A2838 | info @ 15% on slate-900 |

---

## 2. Neutral Scale (Tailwind Slate)

Gray scale for text, backgrounds, and borders. Adopted from Tailwind CSS for consistency with modern web standards.

| Token | Hex | Usage |
|-------|-----|-------|
| `slate-50` | #F8FAFC | Lightest background |
| `slate-100` | #F1F5F9 | Muted background, subtle borders |
| `slate-200` | #E2E8F0 | Default borders, dividers |
| `slate-300` | #CBD5E1 | Strong borders |
| `slate-400` | #94A3B8 | Tertiary text (light), secondary text (dark) |
| `slate-500` | #64748B | Secondary text (light), tertiary text (dark) |
| `slate-600` | #475569 | - |
| `slate-700` | #334155 | Muted background (dark) |
| `slate-800` | #1E293B | Primary text (light), surface background (dark) |
| `slate-900` | #0F172A | Page background (dark) |
| `slate-950` | #020617 | Deepest dark |

---

## 3. Derived Tokens

Semantic mappings from the neutral scale. These provide consistent, purpose-driven access to the palette.

### Text Colors

| Token | Light | Dark | Slate Mapping |
|-------|-------|------|---------------|
| `text-primary` | #1E293B | #F1F5F9 | slate-800 / slate-100 |
| `text-secondary` | #64748B | #94A3B8 | slate-500 / slate-400 |
| `text-tertiary` | #94A3B8 | #64748B | slate-400 / slate-500 |
| `text-disabled` | #CBD5E1 | #475569 | slate-300 / slate-600 |
| `text-inverse` | #FFFFFF | #0F172A | white / slate-900 |

### Background Colors

| Token | Light | Dark | Slate Mapping |
|-------|-------|------|---------------|
| `bg-page` | #F8FAFC | #0F172A | slate-50 / slate-900 |
| `bg-surface` | #FFFFFF | #1E293B | white / slate-800 |
| `bg-muted` | #F1F5F9 | #334155 | slate-100 / slate-700 |
| `bg-elevated` | #FFFFFF | #334155 | white / slate-700 |
| `bg-inverse` | #1E293B | #F1F5F9 | slate-800 / slate-100 |
| `bg-overlay` | rgba(0,0,0,0.5) | rgba(0,0,0,0.7) | - |

### Border Colors

| Token | Light | Dark | Slate Mapping |
|-------|-------|------|---------------|
| `border-default` | #E2E8F0 | #334155 | slate-200 / slate-700 |
| `border-subtle` | #F1F5F9 | #1E293B | slate-100 / slate-800 |
| `border-strong` | #CBD5E1 | #475569 | slate-300 / slate-600 |
| `border-focus` | #4A7BA7 | #6A9BC7 | primary |

### Link Colors

| Token | Light | Dark | Source |
|-------|-------|------|--------|
| `link-default` | #4A7BA7 | #6A9BC7 | primary |
| `link-hover` | #3D6A94 | #8ABBDD | primary-hover / lightened |
| `link-visited` | #7C68A8 | #9C88C8 | accent |
| `link-active` | #3D6A94 | #7AABDA | primary-hover |

---

## 4. Brand Colors

Colors from the Contextify logomark gradient. Used for brand expression, not general UI.

| Token | Hex | Position |
|-------|-----|----------|
| `brand-yellow` | #F9B233 | Left loop |
| `brand-cyan` | #4AC4E0 | Center crossing |
| `brand-purple` | #8B5CF6 | Right loop |

**Gradient:** `linear-gradient(135deg, #F9B233 0%, #4AC4E0 50%, #8B5CF6 100%)`

**Usage:**
- Logomark
- Brand dividers
- Hover accents on cards
- Special promotional elements

---

## 5. Provider Colors

Third-party brand colors for AI providers. Must match their official brand guidelines.

| Token | Hex | Provider | Notes |
|-------|-----|----------|-------|
| `provider-claude` | #D97757 | Claude Code | Anthropic coral |
| `provider-codex` | #FFFFFF | Codex CLI | Requires shadow on light backgrounds |

---

## 6. Dark Mode Derivation

Dark mode colors are derived systematically, not arbitrarily chosen.

### Derivation Rules

| Category | Light → Dark Transformation |
|----------|----------------------------|
| **Backgrounds** | Invert slate scale (50→900, 100→800, etc.) |
| **Text** | Invert slate scale (800→100, 500→400, etc.) |
| **Semantic colors** | Lift lightness +15% for vibrancy |
| **Semantic -light** | 15% opacity on slate-900 instead of 10% on white |
| **Borders** | Invert slate scale (200→700, 100→800, etc.) |
| **Brand colors** | Unchanged (logo is fixed) |
| **Provider colors** | Unchanged (third-party brands) |

### Why These Rules

1. **Slate inversion** maintains relative contrast relationships
2. **Semantic lifting** compensates for dark backgrounds absorbing color
3. **Higher opacity for -light variants** in dark mode provides sufficient contrast
4. **Brand/provider unchanged** preserves external identity

---

## 7. Implementation

### CSS

```css
:root {
  /* Semantic */
  --contextify-primary: #4A7BA7;
  --contextify-primary-hover: #3D6A94;
  --contextify-primary-light: #E8F0F7;
  --contextify-secondary: #9B8B7E;
  --contextify-success: #51A86B;
  --contextify-success-light: #E8F5EC;
  --contextify-warning: #D4A84E;
  --contextify-warning-light: #FDF6E8;
  --contextify-error: #C74E4E;
  --contextify-error-light: #FBEAEA;
  --contextify-info: #4A7BA7;
  --contextify-info-light: #E8F0F7;
  --contextify-accent: #7C68A8;

  /* Neutral (Tailwind Slate) */
  --slate-50: #F8FAFC;
  --slate-100: #F1F5F9;
  --slate-200: #E2E8F0;
  --slate-300: #CBD5E1;
  --slate-400: #94A3B8;
  --slate-500: #64748B;
  --slate-600: #475569;
  --slate-700: #334155;
  --slate-800: #1E293B;
  --slate-900: #0F172A;
  --slate-950: #020617;

  /* Derived - Light Mode */
  --text-primary: var(--slate-800);
  --text-secondary: var(--slate-500);
  --text-tertiary: var(--slate-400);
  --text-disabled: var(--slate-300);
  --text-inverse: #FFFFFF;

  --bg-page: var(--slate-50);
  --bg-surface: #FFFFFF;
  --bg-muted: var(--slate-100);
  --bg-elevated: #FFFFFF;
  --bg-inverse: var(--slate-800);

  --border-default: var(--slate-200);
  --border-subtle: var(--slate-100);
  --border-strong: var(--slate-300);
  --border-focus: var(--contextify-primary);

  --link-default: var(--contextify-primary);
  --link-hover: var(--contextify-primary-hover);
  --link-visited: var(--contextify-accent);

  /* Brand */
  --brand-yellow: #F9B233;
  --brand-cyan: #4AC4E0;
  --brand-purple: #8B5CF6;
  --brand-gradient: linear-gradient(135deg, var(--brand-yellow) 0%, var(--brand-cyan) 50%, var(--brand-purple) 100%);

  /* Provider */
  --provider-claude: #D97757;
  --provider-codex: #FFFFFF;
}

/* Dark Mode */
@media (prefers-color-scheme: dark) {
  :root {
    --contextify-primary: #6A9BC7;
    --contextify-primary-hover: #7AABDA;
    --contextify-primary-light: #1E3A52;
    --contextify-secondary: #B5A89D;
    --contextify-success: #6BC885;
    --contextify-success-light: #1A3028;
    --contextify-warning: #E4B85E;
    --contextify-warning-light: #3A3020;
    --contextify-error: #D76E6E;
    --contextify-error-light: #3A2020;
    --contextify-info: #6A9BC7;
    --contextify-info-light: #1A2838;
    --contextify-accent: #9C88C8;

    --text-primary: var(--slate-100);
    --text-secondary: var(--slate-400);
    --text-tertiary: var(--slate-500);
    --text-disabled: var(--slate-600);
    --text-inverse: var(--slate-900);

    --bg-page: var(--slate-900);
    --bg-surface: var(--slate-800);
    --bg-muted: var(--slate-700);
    --bg-elevated: var(--slate-700);
    --bg-inverse: var(--slate-100);

    --border-default: var(--slate-700);
    --border-subtle: var(--slate-800);
    --border-strong: var(--slate-600);

    --link-hover: #8ABBDD;
    --link-visited: #9C88C8;
  }
}
```

### Swift

```swift
import SwiftUI

// MARK: - Semantic Colors
extension Color {
    static let contextifyPrimary = Color(hex: "#4A7BA7")
    static let contextifyPrimaryHover = Color(hex: "#3D6A94")
    static let contextifySecondary = Color(hex: "#9B8B7E")
    static let contextifySuccess = Color(hex: "#51A86B")
    static let contextifyWarning = Color(hex: "#D4A84E")
    static let contextifyError = Color(hex: "#C74E4E")
    static let contextifyInfo = Color(hex: "#4A7BA7")
    static let contextifyAccent = Color(hex: "#7C68A8")
}

// MARK: - Neutral Scale (Tailwind Slate)
extension Color {
    static let slate50 = Color(hex: "#F8FAFC")
    static let slate100 = Color(hex: "#F1F5F9")
    static let slate200 = Color(hex: "#E2E8F0")
    static let slate300 = Color(hex: "#CBD5E1")
    static let slate400 = Color(hex: "#94A3B8")
    static let slate500 = Color(hex: "#64748B")
    static let slate600 = Color(hex: "#475569")
    static let slate700 = Color(hex: "#334155")
    static let slate800 = Color(hex: "#1E293B")
    static let slate900 = Color(hex: "#0F172A")
    static let slate950 = Color(hex: "#020617")
}

// MARK: - Brand Colors
extension Color {
    static let brandYellow = Color(hex: "#F9B233")
    static let brandCyan = Color(hex: "#4AC4E0")
    static let brandPurple = Color(hex: "#8B5CF6")
}

// MARK: - Provider Colors
extension Color {
    static let providerClaude = Color(hex: "#D97757")
    static let providerCodex = Color.white
}
```

---

## 8. Migration Notes

### Current Swift (SharedExtensions.swift)

Existing code uses legacy names:

| Legacy | New Token |
|--------|-----------|
| `contextifyBlue` | `contextify-primary` |
| `contextifyTaupe` | `contextify-secondary` |
| `contextifyGreen` | `contextify-success` |
| `contextifyYellow` | `contextify-warning` |
| `contextifyRed` | `contextify-error` |
| `contextifyPurple` | `contextify-accent` |

Migration is a future task. Legacy names continue to work.

### Current Website (styles.css)

Website uses legacy INSPINIA palette. Migration to this system is in progress via `build/design/website/specimens/website-comparator.html`.
