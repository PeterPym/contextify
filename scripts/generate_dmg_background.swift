#!/usr/bin/env swift

import AppKit
import Foundation

// Generate a simple DMG background image
// 700x400px with a subtle gradient

let width: CGFloat = 700
let height: CGFloat = 400

let image = NSImage(size: NSSize(width: width, height: height))

image.lockFocus()

// Create gradient background (light blue to white)
let gradient = NSGradient(
    colors: [
        NSColor(red: 0.90, green: 0.95, blue: 1.0, alpha: 1.0),  // Light blue
        NSColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1.0)   // Almost white
    ]
)

gradient?.draw(
    in: NSRect(x: 0, y: 0, width: width, height: height),
    angle: 90
)

image.unlockFocus()

// Convert to PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Error: Failed to create PNG data")
    exit(1)
}

// Write to file
let outputPath = "build/assets/dmg/background.png"
let url = URL(fileURLWithPath: outputPath)

do {
    try pngData.write(to: url)
    print("✅ Created DMG background: \(outputPath)")
    print("   Size: 700x400px")
} catch {
    print("Error: Failed to write PNG: \(error)")
    exit(1)
}
