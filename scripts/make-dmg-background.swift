#!/usr/bin/env swift
// Renders the DMG background, in the app's warm cream and amber, at 1x and 2x.
// Run with `swift scripts/make-dmg-background.swift`; writes into Resources/dmg/.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let outDir = root.appendingPathComponent("Resources/dmg")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(scale: CGFloat, name: String) {
    let size = CGSize(width: 600 * scale, height: 400 * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not create bitmap context for \(name)")
    }
    NSGraphicsContext.current = graphicsContext
    let ctx = graphicsContext.cgContext

    let bounds = CGRect(origin: .zero, size: size)
    let cream = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.91, alpha: 1)
    let white = NSColor(calibratedRed: 1.0, green: 0.99, blue: 0.97, alpha: 1)
    let gradient = NSGradient(starting: cream, ending: white)
    gradient?.draw(in: bounds, angle: -90)

    // Two soft amber glows, echoing AirBackground's corner highlights.
    func glow(_ color: NSColor, center: CGPoint, radius: CGFloat) {
        let glowGradient = NSGradient(starting: color, ending: color.withAlphaComponent(0))
        glowGradient?.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius)
    }
    glow(NSColor(calibratedRed: 0.98, green: 0.68, blue: 0.16, alpha: 0.22), center: CGPoint(x: size.width * 0.12, y: size.height * 0.88), radius: size.width * 0.45)
    glow(NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.55, alpha: 0.28), center: CGPoint(x: size.width * 0.88, y: size.height * 0.1), radius: size.width * 0.4)

    // An arrow between the app and the Applications link, where create-dmg places them.
    let arrowY = size.height * 0.52
    let arrow = NSBezierPath()
    let shaftStart = CGPoint(x: size.width * 0.40, y: arrowY)
    let shaftEnd = CGPoint(x: size.width * 0.58, y: arrowY)
    arrow.move(to: shaftStart)
    arrow.line(to: shaftEnd)
    arrow.lineWidth = 3 * scale
    NSColor(calibratedWhite: 0.6, alpha: 0.5).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: shaftEnd.x - 10 * scale, y: shaftEnd.y - 8 * scale))
    head.line(to: shaftEnd)
    head.line(to: CGPoint(x: shaftEnd.x - 10 * scale, y: shaftEnd.y + 8 * scale))
    head.lineWidth = 3 * scale
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.6, alpha: 0.5).setStroke()
    head.stroke()

    ctx.flush()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(name)")
    }
    try? png.write(to: outDir.appendingPathComponent(name))
    print("wrote \(outDir.appendingPathComponent(name).path)")
}

render(scale: 1, name: "background.png")
render(scale: 2, name: "background@2x.png")
