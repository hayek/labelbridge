// usage: swift make-banner.swift <printer.png> <labels dir> <out.png>
import AppKit

let args = CommandLine.arguments
let photo = NSImage(contentsOfFile: args[1])!
let labelsDir = args[2]
let outPath = args[3]
let W: CGFloat = 1920, H: CGFloat = 1080

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
let flipped = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
NSGraphicsContext.current = flipped
let cg = flipped.cgContext
cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)   // top-left origin

// Background colour sampled from the photo's corner.
let photoRep = NSBitmapImageRep(data: photo.tiffRepresentation!)!
let bg = photoRep.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
bg.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

// Photo: scaled to the banner height, shifted right, left edge faded into the background.
let scale = H / photoRep.size.height * 1.02
let pw = photoRep.size.width * scale, ph = photoRep.size.height * scale
let px = W - pw + 230, py = (H - ph) / 2 + 10
photo.draw(in: NSRect(x: px, y: py, width: pw, height: ph), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
let fade = NSGradient(colors: [bg, bg.withAlphaComponent(0)])!
fade.draw(in: NSRect(x: px - 2, y: 0, width: 260, height: H), angle: 0)
// subtle blue glow top-left
NSGradient(colors: [NSColor(red: 0.25, green: 0.35, blue: 0.85, alpha: 0.16), NSColor(red: 0.25, green: 0.35, blue: 0.85, alpha: 0)])!
    .draw(fromCenter: NSPoint(x: 200, y: 120), radius: 0, toCenter: NSPoint(x: 200, y: 120), radius: 900, options: [])

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont { NSFont.systemFont(ofSize: size, weight: weight) }
func draw(_ s: NSAttributedString, at p: NSPoint) { s.draw(at: p) }
let left: CGFloat = 110

// Eyebrow
let accent = NSColor(red: 0.55, green: 0.66, blue: 1.0, alpha: 1)
accent.setFill(); NSBezierPath(ovalIn: NSRect(x: left, y: 106, width: 13, height: 13)).fill()
draw(NSAttributedString(string: "MACOS · BLUETOOTH LE · OPEN SOURCE", attributes: [
    .font: font(26, .semibold), .foregroundColor: accent, .kern: 2.0]), at: NSPoint(x: left + 28, y: 96))

// Title with a soft vertical gradient (drawn as a mask).
let title = NSAttributedString(string: "LabelBridge", attributes: [.font: font(158, .heavy), .kern: -5.0, .foregroundColor: NSColor.white])
let tSize = title.size()
let tImage = NSImage(size: tSize, flipped: true) { r in
    title.draw(at: .zero)
    NSGraphicsContext.current!.compositingOperation = .sourceIn
    NSGradient(colors: [.white, NSColor(white: 0.80, alpha: 1)])!.draw(in: r, angle: 90)
    return true
}
tImage.draw(in: NSRect(x: left - 6, y: 140, width: tSize.width, height: tSize.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

// Subtitle
let grey = NSColor(white: 0.70, alpha: 1)
let sub = NSMutableAttributedString()
for (text, strong) in [("Print labels to a ", false), ("NIIMBOT D11", true), (" from your Mac, ", false), ("over Bluetooth", true), (".", false)] {
    sub.append(NSAttributedString(string: text, attributes: [.font: font(36, strong ? .bold : .medium), .foregroundColor: strong ? NSColor.white : grey, .kern: -0.6]))
}
draw(sub, at: NSPoint(x: left, y: 340))

// Features, 2 x 2
let features: [(String, String)] = [
    ("list.bullet", "Batch labels from a list"),
    ("character.bubble", "Any language, incl. RTL"),
    ("terminal", "CLI for AI agents"),
    ("printer", "Print dialog in every app"),
]
let orange = NSColor(red: 1.0, green: 0.72, blue: 0.45, alpha: 1)
for (i, f) in features.enumerated() {
    let x = left + CGFloat(i % 2) * 450, y = 450 + CGFloat(i / 2) * 82
    let tile = NSRect(x: x, y: y, width: 56, height: 56)
    NSColor(white: 1, alpha: 0.07).setFill(); NSBezierPath(roundedRect: tile, xRadius: 13, yRadius: 13).fill()
    NSColor(white: 1, alpha: 0.12).setStroke(); let b = NSBezierPath(roundedRect: tile.insetBy(dx: 0.5, dy: 0.5), xRadius: 13, yRadius: 13); b.lineWidth = 1; b.stroke()
    let cfg = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium).applying(.init(paletteColors: [orange]))
    if let sym = NSImage(systemSymbolName: f.0, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let s = sym.size
        sym.draw(in: NSRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2, width: s.width, height: s.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    draw(NSAttributedString(string: f.1, attributes: [.font: font(31, .semibold), .foregroundColor: NSColor(white: 0.94, alpha: 1), .kern: -0.4]),
         at: NSPoint(x: x + 76, y: y + 9))
}

// Real labels rendered by LabelBridge, as white stickers (15 x 50 mm; 12 mm print band centred).
let files = (try! FileManager.default.contentsOfDirectory(atPath: labelsDir)).filter { $0.hasSuffix(".png") }.sorted()
let lw: CGFloat = 400, lh = lw * 15 / 50
let spots: [(CGFloat, CGFloat, CGFloat)] = [(left, 690, -2.5), (left + 430, 676, 2.0), (left + 18, 840, 1.5), (left + 450, 830, -1.8)]
for (i, file) in files.prefix(4).enumerated() {
    let img = NSImage(contentsOfFile: labelsDir + "/" + file)!
    let (x, y, angle) = spots[i]
    cg.saveGState()
    cg.translateBy(x: x + lw / 2, y: y + lh / 2)
    cg.rotate(by: angle * .pi / 180)
    let r = NSRect(x: -lw / 2, y: -lh / 2, width: lw, height: lh)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.55); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    NSColor(white: 0.97, alpha: 1).setFill(); NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.restoreGraphicsState()
    let band = lh * 12 / 15
    img.draw(in: NSRect(x: r.minX, y: -band / 2, width: lw, height: band), from: .zero, operation: .multiply, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    cg.restoreGState()
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
