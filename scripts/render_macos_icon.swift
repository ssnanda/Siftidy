#!/usr/bin/env swift
import AppKit

// Siftidy's vector-style Dock/Finder icon. Runs with macOS/Xcode only.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift render_macos_icon.swift OUTPUT.png\n", stderr)
    exit(2)
}
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Cannot create macOS icon graphics context")
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}
func rounded(_ rect: NSRect, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func mountain(_ points: [NSPoint], fill: NSColor) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    path.close()
    fill.setFill()
    path.fill()
}
func photoCard(
    x: CGFloat, y: CGFloat, w: CGFloat, rotation: CGFloat,
    background: NSColor, border: NSColor, detailed: Bool
) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: x + w / 2, yBy: y + w / 2)
    transform.rotate(byDegrees: rotation)
    transform.translateX(by: -w / 2, yBy: -w / 2)
    transform.concat()
    rounded(NSRect(x: 0, y: 0, width: w, height: w), 76, border)
    let edge: CGFloat = 22
    rounded(NSRect(x: edge, y: edge, width: w - 2 * edge, height: w - 2 * edge),
            58, background)
    if detailed {
        let side = w - edge * 2
        // Distinctive yellow sun and layered cool-blue mountain range.
        let sun = NSBezierPath(ovalIn: NSRect(x: edge + side * 0.69,
            y: edge + side * 0.68, width: side * 0.22, height: side * 0.22))
        color(255, 198, 55).setFill()
        sun.fill()
        mountain([
            NSPoint(x: edge + 12, y: edge + 55),
            NSPoint(x: edge + side * 0.31, y: edge + side * 0.64),
            NSPoint(x: edge + side * 0.58, y: edge + side * 0.33),
            NSPoint(x: edge + side * 0.73, y: edge + side * 0.50),
            NSPoint(x: edge + side - 12, y: edge + 64),
            NSPoint(x: edge + side - 12, y: edge + 12),
            NSPoint(x: edge + 12, y: edge + 12),
        ], fill: color(170, 234, 254))
        mountain([
            NSPoint(x: edge + 90, y: edge + 12),
            NSPoint(x: edge + side * 0.61, y: edge + side * 0.48),
            NSPoint(x: edge + side - 12, y: edge + 78),
            NSPoint(x: edge + side - 12, y: edge + 12),
        ], fill: color(61, 159, 210))
    }
    NSGraphicsContext.restoreGraphicsState()
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true

// Standard bright macOS rounded-square canvas.
rounded(NSRect(x: 16, y: 16, width: 992, height: 992),
        226, color(248, 252, 252))
photoCard(x: 215, y: 190, w: 615, rotation: 9,
          background: color(9, 148, 160), border: color(0, 110, 119),
          detailed: false)
photoCard(x: 176, y: 215, w: 615, rotation: -8,
          background: color(12, 170, 181), border: .white,
          detailed: true)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot serialize Mac icon PNG")
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("Generated Siftidy macOS icon")
