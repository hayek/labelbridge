import AppKit

public enum Alignment: String, Codable, Sendable, CaseIterable { case center, leading, trailing }

public struct TextStyle: Codable, Hashable, Sendable {
    public static let fontSizeRange = 1.0...72.0
    public var fontName: String?
    public var bold: Bool
    public var alignment: Alignment
    public var italic: Bool
    /// Physical points (1/72 inch); nil keeps the existing automatic fit-to-object behavior.
    public var fontSizePoints: Double?

    public init(fontName: String? = nil, bold: Bool = false, alignment: Alignment = .center,
                italic: Bool = false, fontSizePoints: Double? = nil) {
        self.fontName = fontName
        self.bold = bold
        self.alignment = alignment
        self.italic = italic
        self.fontSizePoints = fontSizePoints
    }

    private enum CodingKeys: String, CodingKey { case fontName, bold, alignment, italic, fontSizePoints }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try values.decodeIfPresent(String.self, forKey: .fontName)
        bold = try values.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        alignment = try values.decodeIfPresent(Alignment.self, forKey: .alignment) ?? .center
        italic = try values.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        fontSizePoints = try values.decodeIfPresent(Double.self, forKey: .fontSizePoints)
        try validate()
    }

    func validate() throws {
        if let points = fontSizePoints, !points.isFinite || !Self.fontSizeRange.contains(points) {
            throw TextStyleError.invalidFontSize
        }
    }
}

enum TextStyleError: LocalizedError {
    case invalidFontSize
    var errorDescription: String? { "Font size must be between 1 and 72 pt." }
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
        let margin = LabelSize.endMarginPixels
        let availableWidth = CGFloat(length - 2 * margin)
        let usableHeight = CGFloat(height) - 2 * verticalPadding
        let (block, truncated) = fittedBlock(text, style: style, width: Int(availableWidth), height: Int(usableHeight))

        // Copy the inked rows into the label, centred vertically, between the end margins.
        var pixels = [Bool](repeating: false, count: length * height)
        let inkHeight = min(block.inkHeight, height)
        let dstTop = (height - inkHeight) / 2
        for row in 0..<inkHeight {
            let srcY = block.inkTop + row, dstY = dstTop + row
            for x in 0..<block.width where block.isBlack(x, srcY) { pixels[dstY * length + margin + x] = true }
        }
        let warning = truncated ? "Text too long for a \(size) mm label; shortened with \"…\": \(text.prefix(40))" : nil
        return RenderResult(bitmap: Bitmap(width: length, height: height, pixels: pixels), warning: warning)
    }

    /// Fits actual ink rather than font metrics, including fallback fonts and right-to-left shaping.
    static func fittedBlock(_ text: String, style: TextStyle, width: Int, height: Int) -> (Block, Bool) {
        let lines = text.components(separatedBy: "\n")
        func widthFits(_ font: NSFont) -> Bool { lines.allSatisfy { measure($0, font: font) <= CGFloat(width) } }
        if let points = style.fontSizePoints {
            let font = makeFont(style, CGFloat(points * LabelSize.dpi / 72))
            return (drawBlock(lines, font: font, style: style, width: width), !widthFits(font))
        }
        func fits(_ px: CGFloat) -> Bool {
            let font = makeFont(style, px)
            guard widthFits(font) else { return false }
            return drawBlock(lines, font: font, style: style, width: width, keepPixels: false).inkHeight <= height
        }
        var lo = minFontPixels, hi = CGFloat(height) + 2 * verticalPadding
        if fits(lo) {
            while hi - lo > 0.5 { let mid = (lo + hi) / 2; if fits(mid) { lo = mid } else { hi = mid } }
        }
        let font = makeFont(style, lo)
        return (drawBlock(lines, font: font, style: style, width: width), !widthFits(font))
    }

    struct Block {
        let width: Int
        let inkTop: Int
        let inkHeight: Int
        let isBlack: (Int, Int) -> Bool
    }

    /// Draws the lines (each truncated to `width`) on a tall scratch canvas and finds the rows that contain ink.
    static func drawBlock(_ lines: [String], font: NSFont, style: TextStyle, width: Int, keepPixels: Bool = true) -> Block {
        let heights = lines.map { lineHeight($0, font: font) }
        let pad = ceil(font.pointSize)                     // room for glyphs that overhang their line
        let canvasHeight = Int(heights.reduce(0, +) + 2 * pad)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: canvasHeight,
                                   bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: canvasHeight).fill()
        var top = CGFloat(canvasHeight) - pad               // AppKit y grows upward
        for (line, lh) in zip(lines, heights) {
            let para = NSMutableParagraphStyle()
            para.baseWritingDirection = .natural
            para.lineBreakMode = .byTruncatingTail
            para.alignment = textAlignment(style.alignment, rtl: isRightToLeft(line))
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: para]
            NSAttributedString(string: line, attributes: attrs)
                .draw(with: NSRect(x: 0, y: top - lh, width: CGFloat(width), height: lh),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            top -= lh
        }
        NSGraphicsContext.restoreGraphicsState()

        let data = rep.bitmapData!, bpr = rep.bytesPerRow
        func black(_ x: Int, _ y: Int) -> Bool { data[y * bpr + x] < 128 }
        var first = -1, last = -1
        for y in 0..<canvasHeight {
            let row = data + y * bpr
            var inked = false
            for x in 0..<width where row[x] < 128 { inked = true; break }
            if inked { if first < 0 { first = y }; last = y }
        }
        if first < 0 || !keepPixels { return Block(width: width, inkTop: max(first, 0), inkHeight: first < 0 ? 0 : last - first + 1, isBlack: { _, _ in false }) }
        // Copy pixels out so the closure doesn't depend on the bitmap's lifetime.
        let snapshot = (0..<(canvasHeight * width)).map { black($0 % width, $0 / width) }
        return Block(width: width, inkTop: first, inkHeight: last - first + 1, isBlack: { x, y in snapshot[y * width + x] })
    }

    /// Keeps glyphs off the very edge of the print band.
    static let verticalPadding: CGFloat = 3

    static func lineHeight(_ line: String, font: NSFont) -> CGFloat {
        let text = line.isEmpty ? " " : line
        let laidOut = NSAttributedString(string: text, attributes: [.font: font])
            .boundingRect(with: CGSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(laidOut.height)
    }

    static func makeFont(_ style: TextStyle, _ px: CGFloat) -> NSFont {
        let chosen = style.fontName.flatMap {
            NSFont(name: $0, size: px) ?? NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: px)
        }
        let font: NSFont
        if let chosen {
            font = style.bold ? NSFontManager.shared.convert(chosen, toHaveTrait: .boldFontMask) : chosen
        } else {
            font = style.bold ? .boldSystemFont(ofSize: px) : .systemFont(ofSize: px)
        }
        return style.italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
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
