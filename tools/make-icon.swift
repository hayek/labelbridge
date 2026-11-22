// Draws the app icon (1024×1024) and writes an .iconset for `iconutil`.
// Usage: swift tools/make-icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // macOS icon grid: 824/1024 rounded square with a soft shadow
    let inset = s * 100 / 1024, rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = s * 0.02; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
    NSGradient(colors: [NSColor(red: 0.16, green: 0.42, blue: 0.98, alpha: 1), NSColor(red: 0.07, green: 0.20, blue: 0.62, alpha: 1)])!
        .draw(in: shape, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()
    // white label with a hole, tilted
    let label = NSRect(x: rect.midX - rect.width * 0.34, y: rect.midY - rect.height * 0.14, width: rect.width * 0.68, height: rect.height * 0.28)
    let t = NSAffineTransform(); t.translateX(by: rect.midX, yBy: rect.midY); t.rotate(byDegrees: 12); t.translateX(by: -rect.midX, yBy: -rect.midY)
    NSGraphicsContext.current?.saveGraphicsState()
    t.concat()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: label, xRadius: label.height * 0.18, yRadius: label.height * 0.18).fill()
    // text lines on the label
    NSColor(red: 0.07, green: 0.20, blue: 0.62, alpha: 1).setFill()
    let lineX = label.minX + label.width * 0.30
    NSBezierPath(roundedRect: NSRect(x: lineX, y: label.midY + label.height * 0.06, width: label.width * 0.56, height: label.height * 0.16), xRadius: 6 * s / 1024, yRadius: 6 * s / 1024).fill()
    NSBezierPath(roundedRect: NSRect(x: lineX, y: label.midY - label.height * 0.24, width: label.width * 0.40, height: label.height * 0.16), xRadius: 6 * s / 1024, yRadius: 6 * s / 1024).fill()
    // Bluetooth mark on the left of the label
    if let bt = NSImage(systemSymbolName: "wave.3.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: label.height * 0.55, weight: .bold)) {
        let tinted = NSImage(size: bt.size, flipped: false) { r in
            bt.draw(in: r); NSColor(red: 0.16, green: 0.42, blue: 0.98, alpha: 1).set(); r.fill(using: .sourceAtop); return true
        }
        let w = label.height * 0.62, h = w * bt.size.height / bt.size.width
        tinted.draw(in: NSRect(x: label.minX + label.width * 0.07, y: label.midY - h / 2, width: w, height: h))
    }
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
