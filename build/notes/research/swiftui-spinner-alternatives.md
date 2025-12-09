# SwiftUI Spinner & Loading Indicator Alternatives

Research compiled: 2025-12-09

## Native SwiftUI Options

### 1. Standard ProgressView (Current Default)

```swift
ProgressView()                          // Default circular spinner
ProgressView().controlSize(.small)      // Smaller variant
ProgressView().scaleEffect(1.5)         // Scaled up
```

### 2. SF Symbol with Animation Effects

Using `symbolEffect()` modifier (SF Symbols 5+):

```swift
Image(systemName: "arrow.trianglehead.2.clockwise")
    .symbolEffect(.rotate, options: .repeating)
```

**Available indefinite animations:**
- **`.rotate`** - Continuous rotation (great for sync/refresh icons)
- **`.pulse`** - Pulsing effect
- **`.pulse.byLayer`** - Layered pulsing (animates symbol layers sequentially)
- **`.variableColor`** - Animated color layers
- **`.scale`** - Scale up/down effect

**Animation behaviors:**
- **Discrete** - One-off animation then stops
- **Indefinite** - Continuously animates until disabled
- **Transition** - Animates symbol in/out of view

### 3. Custom Rotating Circle

```swift
@State private var isAnimating = false

Circle()
    .trim(from: 0, to: 0.7)
    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
    .onAppear { isAnimating = true }
```

### 4. Three-Dot Pulsing Indicator

Sequential pulsating dots - common "typing" style indicator:

```swift
HStack(spacing: 4) {
    ForEach(0..<3) { index in
        Circle()
            .frame(width: 6, height: 6)
            .scaleEffect(isAnimating ? 1.0 : 0.5)
            .animation(
                .easeInOut(duration: 0.6)
                .repeatForever()
                .delay(Double(index) * 0.2),
                value: isAnimating
            )
    }
}
```

## Third-Party Libraries

### SwiftfulLoadingIndicators
- **URL:** https://github.com/SwiftfulThinking/SwiftfulLoadingIndicators
- **Description:** Lightweight collection with many animation styles
- **Usage:**
  ```swift
  LoadingIndicator(animation: .threeBalls, color: .gray, size: .small)
  ```

### ActivityIndicatorView (Exyte)
- **URL:** https://github.com/exyte/ActivityIndicatorView
- **Description:** Preset indicators including growingArc, gradient, and more
- **Customizable** with standard SwiftUI modifiers

### loading-spinner (hassan31)
- **URL:** https://github.com/hassan31/loading-spinner
- **Description:** Multiple variants with view modifier API
- **Variants:** `.default`, `.circle`, `.dots`, `.gradient`

## Contextify Current Usage

As of 2025-12-09, the codebase uses:

| Location | Implementation |
|----------|----------------|
| StatusBarView (queue processing) | `ProgressView().controlSize(.small)` |
| ContentView (discovery overlay) | `ProgressView().scaleEffect(1.5)` |
| ConversationTimelineView (empty state) | `ProgressView().scaleEffect(0.8)` |
| ProjectsWindow (discovery status) | `ProgressView().controlSize(.small)` |
| TimelineEntryRow (hourglass) | `.symbolEffect(.pulse.byLayer, options: .repeating)` |
| InfoButton (hover) | `.symbolEffect(.pulse, options: .nonRepeating)` |
| StatusBarView (error bounce) | `.symbolEffect(.bounce, value: errorBounceAnimation)` |

## Recommendations by Use Case

| Use Case | Recommended Approach |
|----------|---------------------|
| Status bar indicator | SF Symbol with `.symbolEffect(.pulse)` or `.rotate` |
| Full-screen loading | `ProgressView().scaleEffect(1.5)` with text |
| Inline/compact | `ProgressView().controlSize(.small)` |
| Processing state on icon | Add `.symbolEffect(.pulse.byLayer)` to existing icon |
| Sync/refresh action | `arrow.trianglehead.2.clockwise` with `.rotate` |

## References

- [Hacking with Swift - How to animate SF Symbols](https://www.hackingwithswift.com/quick-start/swiftui/how-to-animate-sf-symbols)
- [Design+Code - SF Symbols 5 Animations](https://designcode.io/swiftui-handbook-sf-symbols-5-animations/)
- [CreateWithSwift - Animating SF Symbols](https://www.createwithswift.com/animating-sf-symbols-with-the-symbol-effect-modifier/)
- [AppCoda - SwiftUI Animation Basics: Building a Loading Indicator](https://www.appcoda.com/swiftui-animation-basics-building-a-loading-indicator/)
