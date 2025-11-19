//
//  InfoButton.swift
//  Contextify
//
//  Reusable (i) icon / info button component for help/tooltip system.
//  Displays (ⓘ) info.circle icon that triggers a popover when clicked.
//  Also known as: info icon, help icon, tooltip icon, (i) button.
//  Includes SwiftUI 6 symbol effects and accessibility support.
//

import SwiftUI

/// Reusable (i) icon / info button that displays an (ⓘ) info icon and triggers a popover
///
/// **Search terms:** info icon, help icon, tooltip icon, (i) button, (i) icon, ⓘ
///
/// Features:
/// - Smooth hover transitions (info.circle → info.circle.fill)
/// - SwiftUI 6 symbol effects (.pulse on hover)
/// - Scale animation (1.0 → 1.1)
/// - Respects reduced motion preferences
/// - Full accessibility support (labels + hints)
/// - Default pointer (no custom cursor)
///
/// Usage:
/// ```swift
/// @State private var showInfo = false
///
/// InfoButton(isPresented: $showInfo)
///     .popover(isPresented: $showInfo) {
///         InfoPopoverContent(
///             title: "Help Title",
///             message: "Help message..."
///         )
///     }
/// ```
struct InfoButton: View {
    /// Binding to control popover visibility
    @Binding var isPresented: Bool

    /// Track hover state for visual feedback
    @State private var isHovering = false

    /// Respect system reduced motion preference
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: isHovering ? "info.circle.fill" : "info.circle")
                .foregroundStyle(isHovering ? .blue : .secondary)
                .font(.caption)
                .imageScale(.medium)
                // SwiftUI 6: Symbol effects for subtle attention
                .symbolEffect(.pulse, options: .nonRepeating, isActive: isHovering)
        }
        .buttonStyle(.plain)
        // Scale effect respects reduced motion
        .scaleEffect(isHovering && !reduceMotion ? 1.1 : 1.0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: isHovering
        )
        .onHover { hovering in
            isHovering = hovering
        }
        // Accessibility
        .accessibilityLabel("More information")
        .accessibilityHint("Shows additional details about this feature")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#Preview("Info Button") {
    struct PreviewContainer: View {
        @State private var showInfo = false

        var body: some View {
            HStack(spacing: 12) {
                Text("Feature Name")
                    .font(.body)

                InfoButton(isPresented: $showInfo)
                    .popover(isPresented: $showInfo) {
                        Text("Help content would appear here")
                            .padding()
                            .frame(width: 200)
                    }
            }
            .padding()
            .frame(width: 300, height: 100)
        }
    }

    return PreviewContainer()
}

#Preview("Multiple Info Buttons") {
    struct MultipleButtonsPreview: View {
        @State private var showInfo1 = false
        @State private var showInfo2 = false
        @State private var showInfo3 = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Setting 1")
                    Spacer()
                    InfoButton(isPresented: $showInfo1)
                }

                HStack {
                    Text("Setting 2")
                    Spacer()
                    InfoButton(isPresented: $showInfo2)
                }

                HStack {
                    Text("Setting 3")
                    Spacer()
                    InfoButton(isPresented: $showInfo3)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    return MultipleButtonsPreview()
}
