//
//  SharedExtensions.swift
//  Contextify
//
//  Shared UI utilities and extensions used across timeline and transcript views.
//  Extracted from TimelineEntryRow.swift and TranscriptInventoryView.swift to avoid duplication.
//

import SwiftUI

// MARK: - Color Palette Extension

extension Color {
    /// Contextify design system color palette
    /// Extracted from TimelineEntryRow.swift to avoid duplication
    /// Full spec: build/notes/design-reference/color-scheme.md

    // Primary colors
    static let contextifyBlue = Color(red: 0.290, green: 0.482, blue: 0.655)   // #4A7BA7 - User/directive actions
    static let contextifyGreen = Color(red: 0.318, green: 0.659, blue: 0.420)  // #51A86B - Completion/success states
    static let contextifyTaupe = Color(red: 0.608, green: 0.545, blue: 0.494)  // #9B8B7E - Assistant messages

    // Secondary colors (projected from palette)
    static let contextifyRed = Color(red: 0.780, green: 0.306, blue: 0.306)    // #C74E4E - Errors/destructive actions
    static let contextifyYellow = Color(red: 0.831, green: 0.659, blue: 0.306) // #D4A84E - Warnings/pending states
    static let contextifyPurple = Color(red: 0.486, green: 0.408, blue: 0.659) // #7C68A8 - Metadata/generated content
}

// MARK: - Date Formatting Extensions

extension Date {
    /// Relative time formatting (e.g., "2 hours ago", "yesterday")
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Absolute timestamp for tooltips
    /// Format: "2:34:15 PM, Tuesday, January 15, 2025"
    var absoluteTimestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a, EEEE, MMMM d, yyyy"
        return formatter.string(from: self)
    }
}
