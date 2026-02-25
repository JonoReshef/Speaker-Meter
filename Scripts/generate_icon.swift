#!/usr/bin/env swift

import AppKit
import CoreGraphics

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Background with rounded rect
    let radius = s * 0.223  // macOS icon corner radius ratio
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Gradient background
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.102, green: 0.102, blue: 0.180, alpha: 1.0),  // #1a1a2e
        CGColor(red: 0.086, green: 0.129, blue: 0.243, alpha: 1.0),  // #16213e
    ]
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0),
                           options: [])

    // Draw equalizer bars
    let barData: [(x: CGFloat, top: CGFloat, bottom: CGFloat)] = [
        (-10, -2, 1),   // shortest outer
        (-6, -6, 5),    // medium
        (-2, -9, 9),    // tallest center
        (2, -4, 3),     // medium-short
        (6, -7, 6),     // medium-tall
        (10, -2, 1),    // shortest outer
    ]

    let scale = s / 40.0
    let centerX = s / 2.0
    let centerY = s / 2.0 - s * 0.03  // slight upward shift for dB text

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round)
    ctx.setLineWidth(2.4 * scale)

    for bar in barData {
        let x = centerX + bar.x * scale
        let y1 = centerY - bar.top * scale
        let y2 = centerY - bar.bottom * scale
        ctx.move(to: CGPoint(x: x, y: y1))
        ctx.addLine(to: CGPoint(x: x, y: y2))
    }
    ctx.strokePath()

    // Draw "dB" text
    let fontSize = s * 0.1
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(white: 1.0, alpha: 0.85),
    ]
    let text = "dB" as NSString
    let textSize = text.size(withAttributes: attrs)
    let textX = (s - textSize.width) / 2.0
    let textY = s * 0.08
    text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    do {
        try pngData.write(to: URL(fileURLWithPath: path))
    } catch {
        print("Failed to write \(path): \(error)")
    }
}

let iconsetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] :
    "Resources/AppIcon.iconset"

// Create iconset directory
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// macOS icon sizes: name -> pixel size
let sizes: [(String, Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for (name, pixelSize) in sizes {
    let image = generateIcon(size: pixelSize)
    let path = "\(iconsetDir)/\(name).png"
    savePNG(image, to: path)
    print("Generated \(name).png (\(pixelSize)x\(pixelSize))")
}

print("Done! Now run: iconutil -c icns \(iconsetDir)")
