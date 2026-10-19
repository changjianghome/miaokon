import AppKit
import Foundation

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = context
context.imageInterpolation = .high
let cg = context.cgContext
cg.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.055, green: 0.10, blue: 0.27, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.62, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.53, blue: 0.72, alpha: 1),
])!
background.draw(in: canvas, angle: 42)

// Subtle diagonal sheen gives the icon depth without competing with the mouse glyph.
let sheen = NSBezierPath()
sheen.move(to: NSPoint(x: 0, y: 740))
sheen.curve(to: NSPoint(x: 1024, y: 1024), controlPoint1: NSPoint(x: 330, y: 1030), controlPoint2: NSPoint(x: 690, y: 1110))
sheen.line(to: NSPoint(x: 1024, y: 705))
sheen.curve(to: NSPoint(x: 0, y: 435), controlPoint1: NSPoint(x: 700, y: 700), controlPoint2: NSPoint(x: 300, y: 450))
sheen.close()
NSColor.white.withAlphaComponent(0.055).setFill()
sheen.fill()

// A clean, upright mouse silhouette with a split-button seam and cyan scroll wheel.
let body = NSBezierPath()
body.move(to: NSPoint(x: 512, y: 858))
body.curve(to: NSPoint(x: 290, y: 650), controlPoint1: NSPoint(x: 512, y: 858), controlPoint2: NSPoint(x: 290, y: 805))
body.line(to: NSPoint(x: 290, y: 430))
body.curve(to: NSPoint(x: 512, y: 166), controlPoint1: NSPoint(x: 290, y: 292), controlPoint2: NSPoint(x: 385, y: 166))
body.curve(to: NSPoint(x: 734, y: 430), controlPoint1: NSPoint(x: 639, y: 166), controlPoint2: NSPoint(x: 734, y: 292))
body.line(to: NSPoint(x: 734, y: 650))
body.curve(to: NSPoint(x: 512, y: 858), controlPoint1: NSPoint(x: 734, y: 805), controlPoint2: NSPoint(x: 512, y: 858))
body.close()

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.015, green: 0.045, blue: 0.14, alpha: 0.45)
shadow.shadowBlurRadius = 38
shadow.shadowOffset = NSSize(width: 0, height: -20)
shadow.set()
NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.79, green: 0.88, blue: 1.0, alpha: 1),
])!.draw(in: body, angle: 90)
NSShadow().set()

let seam = NSBezierPath()
seam.lineCapStyle = .round
seam.lineWidth = 10
seam.move(to: NSPoint(x: 512, y: 820))
seam.line(to: NSPoint(x: 512, y: 730))
seam.move(to: NSPoint(x: 512, y: 580))
seam.line(to: NSPoint(x: 512, y: 520))
NSColor(calibratedRed: 0.25, green: 0.38, blue: 0.61, alpha: 0.48).setStroke()
seam.stroke()

let wheel = NSBezierPath(roundedRect: NSRect(x: 487, y: 605, width: 50, height: 112), xRadius: 25, yRadius: 25)
let wheelShadow = NSShadow()
wheelShadow.shadowColor = NSColor(calibratedRed: 0.0, green: 0.38, blue: 0.63, alpha: 0.32)
wheelShadow.shadowBlurRadius = 16
wheelShadow.shadowOffset = NSSize(width: 0, height: -4)
wheelShadow.set()
NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.88, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.66, blue: 0.91, alpha: 1),
])!.draw(in: wheel, angle: 90)
NSShadow().set()

let highlight = NSBezierPath()
highlight.lineCapStyle = .round
highlight.lineWidth = 6
highlight.move(to: NSPoint(x: 512, y: 685))
highlight.line(to: NSPoint(x: 512, y: 646))
NSColor.white.withAlphaComponent(0.78).setStroke()
highlight.stroke()

NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
