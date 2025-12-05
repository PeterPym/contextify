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

    // Provider colors (third-party brand colors)
    static let providerClaude = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757 - Anthropic coral/orange (Claude Code)
    static let providerCodex = Color.white                                      // Codex CLI (requires shadow on light bg)
}

// MARK: - Date Formatting Extensions

/// Static formatters to avoid O(n) allocations in row rendering
/// Following pattern from TimelineEntryRow.swift (lines 12-23)
fileprivate enum DateFormatters {
    /// Relative time formatter (e.g., "2 hours ago", "yesterday")
    /// Static to avoid allocation on every access
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    /// Absolute timestamp formatter for tooltips
    /// Format: "2:34:15 PM, Tuesday, January 15, 2025"
    /// Static to avoid allocation on every access
    static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a, EEEE, MMMM d, yyyy"
        return formatter
    }()
}

extension Date {
    /// Relative time formatting (e.g., "2 hours ago", "yesterday")
    /// Uses static formatter to avoid O(n) allocations
    var relativeTimeString: String {
        DateFormatters.relative.localizedString(for: self, relativeTo: Date())
    }

    /// Absolute timestamp for tooltips
    /// Format: "2:34:15 PM, Tuesday, January 15, 2025"
    /// Uses static formatter to avoid O(n) allocations
    var absoluteTimestampString: String {
        DateFormatters.absolute.string(from: self)
    }
}
