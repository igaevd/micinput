// Draws the micinput app icon and writes it as an .iconset folder.
// Usage: swift Support/make-icon.swift <output.iconset>   (build.sh turns it into AppIcon.icns)
import AppKit
import SwiftUI

/// Draws the icon in a 1024 × 1024 canvas, origin at the bottom left.
func draw(in context: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = RoundedRectangle(cornerRadius: 186, style: .continuous).path(in: tile).cgPath

    // Soft shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(squircle)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Indigo tile with a gentle glow from the top-left corner.
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let fill = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.47, green: 0.45, blue: 1.00, alpha: 1),
        CGColor(red: 0.22, green: 0.16, blue: 0.78, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(fill, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 880), startRadius: 0,
                               endCenter: CGPoint(x: 300, y: 880), endRadius: 640, options: [])
    context.restoreGState()

    // The microphone: capsule, cradle, stem and base.
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(red: 0.1, green: 0.05, blue: 0.4, alpha: 0.35))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.setStrokeColor(CGColor(gray: 1, alpha: 1))
    context.setLineWidth(46)
    context.setLineCap(.round)

    context.addPath(CGPath(roundedRect: CGRect(x: 420, y: 452, width: 184, height: 330),
                           cornerWidth: 92, cornerHeight: 92, transform: nil))
    context.fillPath()

    context.move(to: CGPoint(x: 350, y: 596))
    context.addLine(to: CGPoint(x: 350, y: 550))
    context.addArc(center: CGPoint(x: 512, y: 550), radius: 162, startAngle: .pi, endAngle: 0, clockwise: false)
    context.addLine(to: CGPoint(x: 674, y: 596))
    context.move(to: CGPoint(x: 512, y: 388))
    context.addLine(to: CGPoint(x: 512, y: 286))
    context.move(to: CGPoint(x: 424, y: 286))
    context.addLine(to: CGPoint(x: 600, y: 286))
    context.strokePath()
    context.endTransparencyLayer()
}

func png(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(in: context)
    return bitmap.representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
