import AppKit

public enum StickerIcon: String, Codable, CaseIterable, Sendable {
    case microwave, ceilingLight = "lamp.ceiling", lightbulb, refrigerator, oven, dishwasher
    case washer, dryer, fan, television = "tv", computer = "desktopcomputer", printer
    case wifi, electricity = "bolt", plug = "powerplug", snowflake, flame, water = "drop"
    case coffee = "cup.and.saucer", food = "fork.knife", home = "house", key, lock
    case heart, star, leaf, car, bicycle, trash, box = "shippingbox"

    public var title: String {
        switch self {
        case .ceilingLight: return "Ceiling light"
        case .lightbulb: return "Light bulb"
        case .television: return "Television"
        case .computer: return "Computer"
        case .electricity: return "Electricity"
        case .plug: return "Power plug"
        case .water: return "Water"
        case .coffee: return "Coffee"
        case .food: return "Food"
        case .home: return "Home"
        case .box: return "Box"
        default: return rawValue.capitalized
        }
    }
}

public enum StickerShape: String, Codable, Hashable, Sendable {
    case rectangle, twoCircles
}

public struct StickerFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func clamped(to size: LabelSize) -> StickerFrame {
        let w = min(max(width, 1), size.lengthMM)
        let h = min(max(height, 1), size.widthMM)
        return StickerFrame(x: min(max(x, 0), size.lengthMM - w), y: min(max(y, 0), size.widthMM - h),
                            width: w, height: h)
    }
}

public enum StickerContent: Codable, Hashable, Sendable {
    case text(String), icon(StickerIcon)
}

public struct StickerObject: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var content: StickerContent
    /// Bounds in millimetres, measured from the top-left corner of the physical label.
    public var frame: StickerFrame
    public var style: TextStyle

    public init(content: StickerContent, frame: StickerFrame, style: TextStyle = TextStyle()) {
        id = UUID()
        self.content = content
        self.frame = frame
        self.style = style
    }

    public var title: String {
        switch content {
        case .text(let text): return text.isEmpty ? "Empty text" : String(text.prefix(24))
        case .icon(let icon): return icon.title
        }
    }

    public var hasContent: Bool {
        switch content {
        case .text(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .icon: return true
        }
    }
}

public struct StickerDesign: Codable, Hashable, Sendable {
    public var size: LabelSize
    public var shape: StickerShape
    public var objects: [StickerObject]

    public init(size: LabelSize, shape: StickerShape, objects: [StickerObject] = []) {
        self.size = size
        self.shape = shape
        self.objects = objects
    }

    public func validate() throws {
        guard size.widthMM.isFinite, size.lengthMM.isFinite,
              (4...200).contains(size.widthMM), (4...200).contains(size.lengthMM),
              size.widthMM <= size.lengthMM,
              shape != .twoCircles || size == LabelSize(14, 28),
              objects.count <= 100, Set(objects.map(\.id)).count == objects.count else {
            throw StickerDesignError.invalidGeometry
        }
        for object in objects {
            try object.style.validate()
            let f = object.frame
            guard [f.x, f.y, f.width, f.height].allSatisfy(\.isFinite),
                  f.width >= 1, f.height >= 1, f.x >= 0, f.y >= 0,
                  f.x + f.width <= size.lengthMM + 0.001, f.y + f.height <= size.widthMM + 0.001 else {
                throw StickerDesignError.invalidGeometry
            }
        }
    }
}

public struct StickerTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var design: StickerDesign

    public init(id: String = UUID().uuidString, name: String, design: StickerDesign) {
        self.id = id
        self.name = name
        self.design = design
    }

    public static let builtIn: [StickerTemplate] = {
        let size = LabelSize(14, 28)
        let appliances = [
            StickerObject(content: .icon(.microwave), frame: .init(x: 3, y: 3, width: 8, height: 8)),
            StickerObject(content: .icon(.ceilingLight), frame: .init(x: 17, y: 3, width: 8, height: 8)),
        ]
        let captions = [
            StickerObject(content: .icon(.microwave), frame: .init(x: 4, y: 2, width: 6, height: 6)),
            StickerObject(content: .text("Kitchen"), frame: .init(x: 2, y: 9, width: 10, height: 3)),
            StickerObject(content: .icon(.ceilingLight), frame: .init(x: 18, y: 2, width: 6, height: 6)),
            StickerObject(content: .text("Light"), frame: .init(x: 16, y: 9, width: 10, height: 3)),
        ]
        let names = [
            StickerObject(content: .text("Label 1"), frame: .init(x: 2, y: 4, width: 10, height: 6)),
            StickerObject(content: .text("Label 2"), frame: .init(x: 16, y: 4, width: 10, height: 6)),
        ]
        return [
            StickerTemplate(id: "appliances", name: "Appliances", design: .init(size: size, shape: .twoCircles, objects: appliances)),
            StickerTemplate(id: "icon-text", name: "Icons + text", design: .init(size: size, shape: .twoCircles, objects: captions)),
            StickerTemplate(id: "names", name: "Names", design: .init(size: size, shape: .twoCircles, objects: names)),
            StickerTemplate(id: "blank-circles", name: "Blank circles", design: .init(size: size, shape: .twoCircles)),
            StickerTemplate(id: "blank-rectangle", name: "Blank rectangle", design: .init(size: .defaultSize, shape: .rectangle)),
        ]
    }()
}

public enum StickerDesignError: LocalizedError {
    case invalidGeometry, unavailableIcon(String)

    public var errorDescription: String? {
        switch self {
        case .invalidGeometry: return "The design has invalid dimensions. Keep objects inside the label and use at most 100 objects."
        case .unavailableIcon(let title): return "The \(title) icon is unavailable on this version of macOS. Choose another icon."
        }
    }
}

/// Produces the same print-band bitmap for preview and printing; paper and selection guides are not ink.
public enum StickerDesignRenderer {
    public static func render(_ design: StickerDesign) throws -> RenderResult {
        try design.validate()
        let scale = LabelSize.dpi / 25.4
        let (width, height) = design.size.canvasPixels
        let physicalHeight = Int((design.size.widthMM * scale).rounded())
        let bandTop = (physicalHeight - height) / 2
        var pixels = [Bool](repeating: false, count: width * height)
        var warnings: [String] = []

        for object in design.objects where object.hasContent {
            let f = object.frame
            let x = Int((f.x * scale).rounded()), y = Int((f.y * scale).rounded())
            let w = max(1, Int((f.width * scale).rounded())), h = max(1, Int((f.height * scale).rounded()))
            let bitmap: Bitmap
            switch object.content {
            case .icon(let icon):
                bitmap = try renderIcon(icon, width: w, height: h)
            case .text(let text):
                let (block, truncated) = TextRenderer.fittedBlock(text.replacingOccurrences(of: "\\n", with: "\n"),
                                                               style: object.style, width: w, height: h)
                let inkHeight = min(block.inkHeight, h)
                let top = (h - inkHeight) / 2
                var textPixels = [Bool](repeating: false, count: w * h)
                for row in 0..<inkHeight {
                    for column in 0..<w where block.isBlack(column, block.inkTop + row) {
                        textPixels[(top + row) * w + column] = true
                    }
                }
                if truncated || block.inkHeight > h { warnings.append("\(object.title): text does not fit; enlarge the object or shorten it.") }
                bitmap = Bitmap(width: w, height: h, pixels: textPixels)
            }
            var clipped = false
            for row in 0..<h {
                for column in 0..<w where bitmap.isBlack(x: column, y: row) {
                    let px = x + column, py = y + row
                    let mmX = (Double(px) + 0.5) / scale, mmY = (Double(py) + 0.5) / scale
                    let insideShape: Bool
                    if design.shape == .twoCircles {
                        let cx = mmX < 14 ? 7.0 : 21.0
                        insideShape = pow(mmX - cx, 2) + pow(mmY - 7, 2) <= 49
                    } else {
                        insideShape = true
                    }
                    guard px >= 0, px < width, py >= bandTop, py < bandTop + height, insideShape else {
                        clipped = true
                        continue
                    }
                    pixels[(py - bandTop) * width + px] = true
                }
            }
            if clipped { warnings.append("\(object.title): some ink is outside the sticker or 12 mm print band. Move or shrink the object.") }
        }
        return RenderResult(bitmap: Bitmap(width: width, height: height, pixels: pixels),
                            warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n"))
    }

    private static func renderIcon(_ icon: StickerIcon, width: Int, height: Int) throws -> Bitmap {
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(max(width, height)), weight: .regular)
            .applying(.init(paletteColors: [.black]))
        guard let image = NSImage(systemSymbolName: icon.rawValue, accessibilityDescription: icon.title)?
            .withSymbolConfiguration(configuration), image.size.width > 0, image.size.height > 0 else {
            throw StickerDesignError.unavailableIcon(icon.title)
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let scale = min(CGFloat(width) / image.size.width, CGFloat(height) / image.size.height)
        let drawn = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: (CGFloat(width) - drawn.width) / 2, y: (CGFloat(height) - drawn.height) / 2,
                              width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.bitmapData!
        let pixels = (0..<(width * height)).map { index in
            let offset = index / width * rep.bytesPerRow + index % width * 4
            return Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2]) < 384
        }
        guard pixels.contains(true) else { throw StickerDesignError.unavailableIcon(icon.title) }
        return Bitmap(width: width, height: height, pixels: pixels)
    }
}
