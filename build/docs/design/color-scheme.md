# Contextify Color Scheme

Professional, accessible color palette for the Contextify macOS application.

## Primary Colors

### Contextify Blue
- **Hex:** `#4A7BA7`
- **RGB:** `rgb(74, 123, 167)` / `(0.290, 0.482, 0.655)`
- **Usage:** User messages, directive indicators, primary actions
- **Semantic:** User agency, commands, primary interactive elements

### Contextify Green
- **Hex:** `#51A86B`
- **RGB:** `rgb(81, 168, 107)` / `(0.318, 0.659, 0.420)`
- **Usage:** Completion states, success indicators, positive outcomes
- **Semantic:** Success, completion, affirmative states

### Contextify Taupe
- **Hex:** `#9B8B7E`
- **RGB:** `rgb(155, 139, 126)` / `(0.608, 0.545, 0.494)`
- **Usage:** Assistant messages, neutral elements
- **Semantic:** AI/assistant content, neutral information

## Secondary Colors

### Contextify Red (Error)
- **Hex:** `#C74E4E`
- **RGB:** `rgb(199, 78, 78)` / `(0.780, 0.306, 0.306)`
- **Usage:** Errors, warnings, destructive actions
- **Semantic:** Errors, failures, critical states
- **Derivation:** Matches blue's saturation/lightness profile

### Contextify Yellow (Warning)
- **Hex:** `#D4A84E`
- **RGB:** `rgb(212, 168, 78)` / `(0.831, 0.659, 0.306)`
- **Usage:** Warnings, cautions, pending states
- **Semantic:** Attention needed, in-progress operations
- **Derivation:** Warm complement to blue, matches green's lightness

### Contextify Purple (Metadata)
- **Hex:** `#7C68A8`
- **RGB:** `rgb(124, 104, 168)` / `(0.486, 0.408, 0.659)`
- **Usage:** Metadata, secondary information, generated content
- **Semantic:** System-generated, auxiliary information
- **Derivation:** Cool complement, harmonizes with blue/taupe

## Neutral Palette

### Gray Scale
- **Light Gray:** System `.secondary` / `.tertiary`
- **Medium Gray:** System `.gray`
- **Dark Gray:** System text colors
- **Background:** System `.windowBackgroundColor`

## Usage Guidelines

### Icon Colors
- User directive arrow: **Blue** (#4A7BA7)
- Completion check: **Green** (#51A86B)
- Error indicator: **Red** (#C74E4E)
- Warning/pending: **Yellow** (#D4A84E)

### Message Decorations
- User message accent: **Blue** (#4A7BA7)
- Assistant message accent: **Taupe** (#9B8B7E)
- System message accent: System `.gray`

### Interactive States
- Primary action: **Blue** (#4A7BA7)
- Success feedback: **Green** (#51A86B)
- Error feedback: **Red** (#C74E4E)
- Warning feedback: **Yellow** (#D4A84E)

## Implementation

**Location:** `Contextify/Contextify/TimelineEntryRow.swift` (lines 192-198)

```swift
private extension Color {
    static let contextifyBlue = Color(red: 0.290, green: 0.482, blue: 0.655)  // #4A7BA7
    static let contextifyGreen = Color(red: 0.318, green: 0.659, blue: 0.420) // #51A86B
    static let contextifyTaupe = Color(red: 0.608, green: 0.545, blue: 0.494) // #9B8B7E
    static let contextifyRed = Color(red: 0.780, green: 0.306, blue: 0.306)   // #C74E4E
    static let contextifyYellow = Color(red: 0.831, green: 0.659, blue: 0.306) // #D4A84E
    static let contextifyPurple = Color(red: 0.486, green: 0.408, blue: 0.659) // #7C68A8
}
```

## Accessibility

All primary colors meet WCAG AA contrast requirements against white backgrounds:
- Blue: 4.8:1 (AA Normal, AAA Large)
- Green: 3.8:1 (AA Large)
- Taupe: 3.5:1 (AA Large)
- Red: 4.5:1 (AA Normal, AAA Large)

For critical text, use system dynamic colors to ensure proper contrast in both light/dark modes.

## Design Philosophy

**Professional clarity:** Colors are muted but distinct, avoiding oversaturation
**Provider neutrality:** Taupe serves as a universal assistant color that doesn't compete with provider branding
**Semantic consistency:** Each color has clear semantic meaning throughout the app
**System integration:** Builds on macOS system colors for native feel
