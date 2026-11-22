import AppKit

public enum Alignment: String, Codable, Sendable, CaseIterable { case center, leading, trailing }

public struct TextStyle: Codable, Hashable, Sendable {
    public var fontName: String?
    public var bold: Bool
    public var alignment: Alignment

    public init(fontName: String? = nil, bold: Bool = false, alignment: Alignment = .center) {
        self.fontName = fontName
        self.bold = bold
        self.alignment = alignment
    }
}

public struct RenderResult: Sendable {
    public let bitmap: Bitmap
    public let warning: String?
}

/// Renders text onto a label, as large as fits. Uses Core Text through AppKit, so shaping and
/// bidirectional order (Hebrew, Arabic, mixed text) are handled by the system.
public enum TextRenderer {
    static let minFontPixels: CGFloat = 14

    public static func render(_ text: String, size: LabelSize, style: TextStyle) -> RenderResult {
        let (length, height) = size.canvasPixels
        let margin = CGFloat(LabelSize.endMarginPixels)
        let available = CGSize(width: CGFloat(length) - 2 * margin, height: CGFloat(height))
        let lines = text.components(separatedBy: "\n")

        // Largest font size where every line fits the width and all lines fit the height.
        func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) }
        func fits(_ px: CGFloat) -> Bool {
            let font = makeFont(style, px)
            guard lineHeight(font) * CGFloat(lines.count) <= available.height else { return false }
            return lines.allSatisfy { measure($0, font: font) <= available.width }
        }
        var lo = minFontPixels, hi = CGFloat(height)
        if fits(lo) {
            while hi - lo > 0.5 { let mid = (lo + hi) / 2; if fits(mid) { lo = mid } else { hi = mid } }
        }
        let fontSize = lo
        let font = makeFont(style, fontSize)
        let truncated = !fits(fontSize)

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: length, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: length, height: height).fill()

        let lh = lineHeight(font)
        let blockHeight = min(lh * CGFloat(lines.count), available.height)
        var top = (CGFloat(height) + blockHeight) / 2          // AppKit y grows upward
        for line in lines {
            let para = NSMutableParagraphStyle()
            para.baseWritingDirection = .natural
            para.lineBreakMode = .byTruncatingTail
            para.alignment = textAlignment(style.alignment, rtl: isRightToLeft(line))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: para]
            let rect = NSRect(x: margin, y: top - lh, width: available.width, height: lh)
            NSAttributedString(string: line, attributes: attrs)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            top -= lh
        }
        NSGraphicsContext.restoreGraphicsState()

        let data = rep.bitmapData!, bpr = rep.bytesPerRow
        var pixels = [Bool](repeating: false, count: length * height)
        for y in 0..<height {
            for x in 0..<length where data[y * bpr + x] < 128 { pixels[y * length + x] = true }
        }
        // Clear the end margins, so glyph overhang can never reach the label edges.
        for y in 0..<height {
            for x in 0..<Int(margin) { pixels[y * length + x] = false; pixels[y * length + length - 1 - x] = false }
        }
        let warning = truncated ? "Text too long for a \(size) mm label; shortened with \"…\": \(text.prefix(40))" : nil
        return RenderResult(bitmap: Bitmap(width: length, height: height, pixels: pixels), warning: warning)
    }

    static func makeFont(_ style: TextStyle, _ px: CGFloat) -> NSFont {
        if let name = style.fontName, let f = NSFont(name: name, size: px) {
            return style.bold ? NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) : f
        }
        return style.bold ? .boldSystemFont(ofSize: px) : .systemFont(ofSize: px)
    }

    static func measure(_ line: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: line, attributes: [.font: font]).size().width)
    }

    static func textAlignment(_ a: Alignment, rtl: Bool) -> NSTextAlignment {
        switch a {
        case .center: return .center
        case .leading: return rtl ? .right : .left
        case .trailing: return rtl ? .left : .right
        }
    }

    /// Direction of the first strong character (Hebrew, Arabic, Syriac, Thaana, NKo and their presentation forms are RTL).
    static func isRightToLeft(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v) { return true }
            if scalar.properties.isAlphabetic { return false }
        }
        return false
    }
}
