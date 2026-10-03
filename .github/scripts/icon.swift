// Draws the app icon: a phosphor CRT prompt on dark glass.
//
// Usage: swift .github/scripts/icon.swift <out.icns>
// The icon is code, not a binary from a design tool, so it can be redrawn
// whenever the palette changes.
import AppKit

let green = NSColor(srgbRed: 0x5B / 255, green: 0xE8 / 255, blue: 0x7F / 255, alpha: 1)

func draw(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { fatalError("bitmap context for \(pixels)px could not be created") }
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let unit = size / 1024
    cg.scaleBy(x: unit, y: unit)

    // macOS icon grid: an 824pt squircle centred on a 1024pt canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the plate.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    cg.addPath(shape)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(shape)
    cg.clip()

    // Glass: a faint green core fading into near-black edges.
    let space = CGColorSpaceCreateDeviceRGB()
    let glass = CGGradient(
        colorsSpace: space,
        colors: [
            NSColor(srgbRed: 0.05, green: 0.13, blue: 0.07, alpha: 1).cgColor,
            NSColor(srgbRed: 0.012, green: 0.03, blue: 0.016, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(
        glass, startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
        endCenter: CGPoint(x: 512, y: 512), endRadius: 600, options: .drawsAfterEndLocation)

    // The prompt: a chevron and a block cursor, both glowing.
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 46, color: green.withAlphaComponent(0.9).cgColor)
    cg.setStrokeColor(green.cgColor)
    cg.setLineWidth(70)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: 290, y: 650))
    cg.addLine(to: CGPoint(x: 450, y: 512))
    cg.addLine(to: CGPoint(x: 290, y: 374))
    cg.strokePath()
    cg.setFillColor(green.cgColor)
    cg.addPath(
        CGPath(
            roundedRect: CGRect(x: 520, y: 340, width: 210, height: 70), cornerWidth: 14,
            cornerHeight: 14, transform: nil))
    cg.fillPath()
    cg.restoreGState()

    // Scanlines over everything inside the glass.
    cg.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
    var line: CGFloat = 100
    while line < 924 {
        cg.fill(CGRect(x: 100, y: line, width: 824, height: 4))
        line += 10
    }

    // Reflection across the upper half of the glass.
    let shine = CGGradient(
        colorsSpace: space,
        colors: [
            NSColor.white.withAlphaComponent(0.13).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(
        shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    cg.restoreGState()

    // Thin bezel so the plate reads on a dark Dock.
    cg.addPath(shape)
    cg.setStrokeColor(green.withAlphaComponent(0.22).cgColor)
    cg.setLineWidth(4)
    cg.strokePath()

    NSGraphicsContext.current = nil
    return rep
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: icon.swift <out.icns>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)  // a stale iconset from a previous run is fine to lose
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        guard let png = draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])
        else { fatalError("PNG encoding of a fresh bitmap cannot fail") }
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
