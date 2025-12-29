//
//  WorktreeColorUtility.swift
//  Contextify
//
//  Provides consistent color assignment for git worktrees.
//  Projects sharing the same git root get the same background tint color.
//

import CryptoKit
import Foundation
import SwiftUI

/// Utility for computing consistent colors based on git root paths.
/// Used to visually group related worktrees in the project tab bar.
public enum WorktreeColorUtility {

  // MARK: - Contextify Design System Colors (from build/design/brand/colors.md)

  /// 10-color accent palette derived from Contextify design system.
  /// - First 5: Semantic UI colors (primary, success, warning, error, accent)
  /// - Next 3: Brand gradient colors (yellow, cyan, purple)
  /// - Last 2: Extended palette (secondary, teal)
  private static let accentColors: [Color] = [
    Color(red: 0.290, green: 0.482, blue: 0.655),  // #4A7BA7 primary
    Color(red: 0.318, green: 0.659, blue: 0.420),  // #51A86B success
    Color(red: 0.831, green: 0.659, blue: 0.306),  // #D4A84E warning
    Color(red: 0.780, green: 0.306, blue: 0.306),  // #C74E4E error
    Color(red: 0.486, green: 0.408, blue: 0.659),  // #7C68A8 accent
    Color(red: 0.976, green: 0.698, blue: 0.200),  // #F9B233 brand-yellow
    Color(red: 0.290, green: 0.769, blue: 0.878),  // #4AC4E0 brand-cyan
    Color(red: 0.545, green: 0.361, blue: 0.965),  // #8B5CF6 brand-purple
    Color(red: 0.608, green: 0.545, blue: 0.494),  // #9B8B7E secondary
    Color(red: 0.353, green: 0.608, blue: 0.667),  // #5A9BAA teal (derived)
  ]

  // MARK: - Public API

  /// Computes a consistent color for a git root path.
  /// The same path always returns the same color (deterministic via SHA256 hash).
  ///
  /// Uses 2 bytes of the hash for better distribution across the color palette,
  /// avoiding accidental clustering when many roots share similar prefixes.
  ///
  /// - Parameter gitRoot: The git repository root URL
  /// - Returns: A color from the accent palette
  public static func color(for gitRoot: URL) -> Color {
    let hash = SHA256.hash(data: Data(gitRoot.path.utf8))
    let colorIndex = hash.withUnsafeBytes { bytes in
      // Use 2 bytes for better distribution
      let value = Int(bytes[0]) << 8 | Int(bytes[1])
      return value % accentColors.count
    }
    return accentColors[colorIndex]
  }

  /// Returns the tint color (18% opacity) for tab backgrounds.
  /// Provides subtle visual grouping without overwhelming the UI.
  /// Slightly higher than 15% for better visibility in dark mode.
  ///
  /// - Parameter gitRoot: The git repository root URL
  /// - Returns: A semi-transparent color suitable for backgrounds
  public static func tintColor(for gitRoot: URL) -> Color {
    color(for: gitRoot).opacity(0.18)
  }

  /// Returns the border color (45% opacity) for active tab borders.
  /// Provides stronger visual emphasis for the currently selected tab.
  ///
  /// - Parameter gitRoot: The git repository root URL
  /// - Returns: A semi-transparent color suitable for borders
  public static func borderColor(for gitRoot: URL) -> Color {
    color(for: gitRoot).opacity(0.45)
  }
}
