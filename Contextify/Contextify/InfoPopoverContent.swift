//
//  InfoPopoverContent.swift
//  Contextify
//
//  Reusable popover content component for help/tooltip system.
//  Displays formatted help text with optional action button.
//  Uses SwiftUI 6 presentationSizing for optimal layout.
//

import SwiftUI

/// Conditional modifier for presentationSizing (macOS 26+ only)
private struct PresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.presentationSizing(.fitted)
        } else {
            // On macOS 15, just use the frame constraints
            content
        }
    }
}

/// Reusable popover content for displaying help information
///
/// Features:
/// - Title + message with proper typography
/// - Optional action button (e.g., "Open Settings")
/// - Close button for explicit dismissal
/// - Native vibrancy (.regularMaterial)
/// - SwiftUI 6 .presentationSizing(.fitted)
/// - Constrained to max width 320pt for readability
/// - Respects dark mode and system colors
///
/// Usage:
/// ```swift
/// .popover(isPresented: $showInfo) {
///     InfoPopoverContent(
///         title: "Apple Intelligence",
///         message: "Explains the feature...",
///         actionLabel: "Open Settings",
///         action: {
///             // Open System Settings
///         }
///     )
/// }
/// ```
struct InfoPopoverContent: View {
    /// Popover title (headline style)
    let title: String

    /// Help message body (supports multi-line)
    let message: String

    /// Optional action button label
    var actionLabel: String?

    /// Optional action to perform
    var action: (() -> Void)?

    /// Environment dismiss action
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and close button
            header

            // Body content
            bodyContent

            // Optional action button
            if let actionLabel, let action {
                Divider()
                    .padding(.vertical, 4)

                actionButton(label: actionLabel, action: action)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)  // Fixed width for consistent sizing
        .fixedSize(horizontal: false, vertical: true)  // Force intrinsic height
        .background(.regularMaterial)  // Native vibrancy effect
        // SwiftUI 6: Explicit sizing control (macOS 26+)
        .modifier(PresentationSizingModifier())
        .presentationCompactAdaptation(.popover)  // Always popover, never sheet
    }

    // MARK: - View Components

    @ViewBuilder
    private var header: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityHint("Dismisses this help popover")
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        // Gate textSelection on macOS 26+ - it causes sizing issues on macOS 15
        if #available(macOS 26, *) {
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(message)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func actionButton(label: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button(label) {
                action()
                dismiss()
            }
            .buttonStyle(.link)
            .foregroundStyle(.blue)
        }
    }
}

// MARK: - Previews

#Preview("Basic Help") {
    struct PreviewContainer: View {
        @State private var showInfo = true

        var body: some View {
            Text("Hover over me")
                .popover(isPresented: $showInfo) {
                    InfoPopoverContent(
                        title: "Feature Explanation",
                        message: "This is a detailed explanation of the feature with multiple lines of helpful information that wraps naturally."
                    )
                }
        }
    }

    return PreviewContainer()
}

#Preview("With Action Button") {
    struct PreviewWithAction: View {
        @State private var showInfo = true

        var body: some View {
            Text("Hover over me")
                .popover(isPresented: $showInfo) {
                    InfoPopoverContent(
                        title: "Apple Intelligence Error",
                        message: """
                        Apple Intelligence is unavailable.

                        To enable:
                        1. Open System Settings
                        2. Go to Apple Intelligence & Siri
                        3. Toggle Apple Intelligence on
                        4. Restart Contextify
                        """,
                        actionLabel: "Open System Settings",
                        action: {
                            print("Opening System Settings...")
                        }
                    )
                }
        }
    }

    return PreviewWithAction()
}

#Preview("Long Content") {
    struct LongContentPreview: View {
        @State private var showInfo = true

        var body: some View {
            Text("Hover over me")
                .popover(isPresented: $showInfo) {
                    InfoPopoverContent(
                        title: "LLM Generation Errors",
                        message: """
                        5 conversation entries failed to generate summaries.

                        Common causes:
                        • Apple Intelligence is disabled or unavailable
                        • Content quality too low (empty messages, no context)
                        • System resources temporarily unavailable

                        What to try:
                        1. Check Apple Intelligence in System Settings
                        2. Ensure sufficient system memory available
                        3. Wait a moment and try refreshing the timeline

                        Errors auto-clear after 3 successful generations.
                        """,
                        actionLabel: "Check System Settings",
                        action: {
                            print("Opening System Settings...")
                        }
                    )
                }
        }
    }

    return LongContentPreview()
}

#Preview("Dark Mode") {
    struct DarkModePreview: View {
        @State private var showInfo = true

        var body: some View {
            Text("Hover over me")
                .popover(isPresented: $showInfo) {
                    InfoPopoverContent(
                        title: "Dark Mode Test",
                        message: "This popover should look great in both light and dark mode thanks to .regularMaterial background."
                    )
                }
                .preferredColorScheme(.dark)
        }
    }

    return DarkModePreview()
}
