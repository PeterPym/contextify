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
  /// All colors explicitly use sRGB color space for consistent rendering.
  private static let accentColors: [Color] = [
    Color(.sRGB, red: 0.290, green: 0.482, blue: 0.655),  // #4A7BA7 primary
    Color(.sRGB, red: 0.318, green: 0.659, blue: 0.420),  // #51A86B success
    Color(.sRGB, red: 0.831, green: 0.659, blue: 0.306),  // #D4A84E warning
    Color(.sRGB, red: 0.780, green: 0.306, blue: 0.306),  // #C74E4E error
    Color(.sRGB, red: 0.486, green: 0.408, blue: 0.659),  // #7C68A8 accent
    Color(.sRGB, red: 0.976, green: 0.698, blue: 0.200),  // #F9B233 brand-yellow
    Color(.sRGB, red: 0.290, green: 0.769, blue: 0.878),  // #4AC4E0 brand-cyan
    Color(.sRGB, red: 0.545, green: 0.361, blue: 0.965),  // #8B5CF6 brand-purple
    Color(.sRGB, red: 0.608, green: 0.545, blue: 0.494),  // #9B8B7E secondary
    Color(.sRGB, red: 0.353, green: 0.608, blue: 0.667),  // #5A9BAA teal (derived)
  ]

  /// Hex color codes corresponding to accentColors (for database storage).
  /// Used when assigning colors to manual groups.
  /// Internal visibility - only used by pickAvailableColor().
  static let accentColorHexCodes: [String] = [
    "#4A7BA7",  // primary
    "#51A86B",  // success
    "#D4A84E",  // warning
    "#C74E4E",  // error
    "#7C68A8",  // accent
    "#F9B233",  // brand-yellow
    "#4AC4E0",  // brand-cyan
    "#8B5CF6",  // brand-purple
    "#9B8B7E",  // secondary
    "#5A9BAA",  // teal
  ]

  /// Named color entry for UI display (color picker menus, etc.)
  public struct NamedColor: Identifiable {
    public let id: String  // hex code
    public let name: String
    public let color: Color
  }

  /// Palette of named colors for UI display.
  /// Used in "Change Group Color" context menu.
  public static let namedPalette: [NamedColor] = [
    NamedColor(id: "#4A7BA7", name: "Blue", color: accentColors[0]),
    NamedColor(id: "#51A86B", name: "Green", color: accentColors[1]),
    NamedColor(id: "#D4A84E", name: "Orange", color: accentColors[2]),
    NamedColor(id: "#C74E4E", name: "Red", color: accentColors[3]),
    NamedColor(id: "#7C68A8", name: "Purple", color: accentColors[4]),
    NamedColor(id: "#F9B233", name: "Yellow", color: accentColors[5]),
    NamedColor(id: "#4AC4E0", name: "Cyan", color: accentColors[6]),
    NamedColor(id: "#8B5CF6", name: "Violet", color: accentColors[7]),
    NamedColor(id: "#9B8B7E", name: "Brown", color: accentColors[8]),
    NamedColor(id: "#5A9BAA", name: "Teal", color: accentColors[9]),
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

  /// Picks an available color from the palette for a new manual group.
  /// Excludes colors already in use by existing groups.
  /// If all colors are in use, picks randomly from the palette.
  ///
  /// - Parameter usedColorHexes: Set of hex codes already used by existing groups
  /// - Returns: A hex color code from the palette (with # prefix)
  public static func pickAvailableColor(excluding usedColorHexes: Set<String>) -> String {
    // Canonicalize used colors for robust comparison
    let normalizedUsed = Set(usedColorHexes.compactMap { canonicalizeHex($0) })

    // Canonicalize palette colors (they're already canonical, but be consistent)
    let canonicalPalette = accentColorHexCodes.compactMap { canonicalizeHex($0) }

    // Find colors not in use
    let available = zip(accentColorHexCodes, canonicalPalette)
      .filter { !normalizedUsed.contains($0.1) }
      .map { $0.0 }

    // Pick randomly from available, or from full palette if all used
    let palette = available.isEmpty ? accentColorHexCodes : available
    return palette.randomElement() ?? accentColorHexCodes[0]
  }

  // MARK: - Private Helpers

  /// Canonicalizes a hex color string for comparison.
  /// - Trims whitespace
  /// - Strips leading # or 0x
  /// - Uppercases
  /// - Truncates to 6 chars (drops alpha if 8 chars)
  /// - Returns nil if result is not exactly 6 hex chars
  private static func canonicalizeHex(_ hex: String) -> String? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

    // Strip common prefixes
    if s.hasPrefix("#") {
      s.removeFirst()
    } else if s.hasPrefix("0X") {
      s.removeFirst(2)
    }

    // Handle 8-char RRGGBBAA by dropping alpha
    if s.count == 8 {
      s = String(s.prefix(6))
    }

    // Validate: must be exactly 6 hex characters
    guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else {
      return nil
    }

    return s
  }
}

// MARK: - Color Hex Extension

extension Color {
  /// Parse a hex color string into a Color.
  /// Supports formats: "#RRGGBB", "RRGGBB", "#RRGGBBAA", "RRGGBBAA"
  public static func fromHex(_ hex: String) -> Color? {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hexString.hasPrefix("#") {
      hexString.removeFirst()
    }

    guard hexString.count == 6 || hexString.count == 8 else {
      return nil
    }

    var rgbValue: UInt64 = 0
    guard Scanner(string: hexString).scanHexInt64(&rgbValue) else {
      return nil
    }

    if hexString.count == 8 {
      // RRGGBBAA format
      let r = Double((rgbValue & 0xFF000000) >> 24) / 255.0
      let g = Double((rgbValue & 0x00FF0000) >> 16) / 255.0
      let b = Double((rgbValue & 0x0000FF00) >> 8) / 255.0
      let a = Double(rgbValue & 0x000000FF) / 255.0
      return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    } else {
      // RRGGBB format
      let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
      let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
      let b = Double(rgbValue & 0x0000FF) / 255.0
      return Color(.sRGB, red: r, green: g, blue: b)
    }
  }
}
