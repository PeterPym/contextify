#!/usr/bin/env swift

import AppKit
import Foundation

// Generate a DMG background image at 2x Retina (1400x800 pixels for 700x400 logical)
// Includes an arrow between the app icon and Applications folder positions

let scale: CGFloat = 2.0
let logicalWidth: CGFloat = 700
let logicalHeight: CGFloat = 400
let pixelWidth = Int(logicalWidth * scale)
let pixelHeight = Int(logicalHeight * scale)

// Icon positions from build/assets/dmg/settings.json (logical coords, top-left origin)
let appX: CGFloat = 160
let appsX: CGFloat = 530
let iconY: CGFloat = 140  // Both icons at same y
let iconSize: CGFloat = 120

// Convert to logical coords in AppKit coordinate system (origin bottom-left)
let appCenterX = appX
let appsCenterX = appsX
let centerY = logicalHeight - iconY  // Flip y for AppKit

// Arrow geometry (logical points) - between icon edges with padding
let iconRadius = iconSize / 2
let arrowPadding: CGFloat = 50  // padding from icon edges
let arrowStartX = appCenterX + iconRadius + arrowPadding
let arrowEndX = appsCenterX - iconRadius - arrowPadding
let arrowY = centerY
let arrowHeadLength: CGFloat = 56
let arrowHeadWidth: CGFloat = 44
let arrowShaftWidth: CGFloat = 24.0

// Create bitmap representation at exact pixel dimensions
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

// Set logical size (144 DPI = 2x Retina)
rep.size = NSSize(width: logicalWidth, height: logicalHeight)

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context

// Drawing in logical coordinates (700x400) - the context scales to fill pixel buffer
let fullRect = NSRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)

// Draw gradient background (light blue to almost white)
let gradient = NSGradient(
    colors: [
        NSColor(red: 0.88, green: 0.94, blue: 1.0, alpha: 1.0),   // Light blue at bottom
        NSColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 1.0)    // Almost white at top
    ]
)!

gradient.draw(in: fullRect, angle: 90)

// Draw arrow (subtle blue-gray, semi-transparent)
let arrowColor = NSColor(red: 0.30, green: 0.40, blue: 0.55, alpha: 0.50)
arrowColor.setFill()

// Draw arrow as a single unified path (no alpha overlap artifacts)
let headBaseX = arrowEndX - arrowHeadLength
let arrowPath = NSBezierPath()
// Start at top-left of shaft
arrowPath.move(to: NSPoint(x: arrowStartX, y: arrowY + arrowShaftWidth / 2))
// Along top of shaft to where head begins
arrowPath.line(to: NSPoint(x: headBaseX, y: arrowY + arrowShaftWidth / 2))
// Up to top of arrowhead
arrowPath.line(to: NSPoint(x: headBaseX, y: arrowY + arrowHeadWidth))
// To tip
arrowPath.line(to: NSPoint(x: arrowEndX, y: arrowY))
// Back to bottom of arrowhead
arrowPath.line(to: NSPoint(x: headBaseX, y: arrowY - arrowHeadWidth))
// Down to bottom of shaft
arrowPath.line(to: NSPoint(x: headBaseX, y: arrowY - arrowShaftWidth / 2))
// Along bottom of shaft back to start
arrowPath.line(to: NSPoint(x: arrowStartX, y: arrowY - arrowShaftWidth / 2))
arrowPath.close()
arrowPath.fill()

NSGraphicsContext.restoreGraphicsState()

// Write PNG
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("Error: Failed to create PNG data")
    exit(1)
}

let outputPath = "build/assets/dmg/background.png"
let url = URL(fileURLWithPath: outputPath)

do {
    try pngData.write(to: url)
    print("Created DMG background: \(outputPath)")
    print("  Pixels: \(pixelWidth)x\(pixelHeight)")
    print("  Logical: \(Int(logicalWidth))x\(Int(logicalHeight)) @2x (144 DPI)")
    print("  Arrow: x=\(Int(arrowStartX))-\(Int(arrowEndX)) at y=\(Int(arrowY)) (logical)")
} catch {
    print("Error: Failed to write PNG: \(error)")
    exit(1)
}
