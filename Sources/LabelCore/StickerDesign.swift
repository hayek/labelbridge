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

extension StickerIcon {
    /// Matches the symbol name ("lamp.ceiling"), the case name ("ceilingLight") or the title ("Ceiling light").
    public init?(named name: String) {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let wanted = key(name)
        guard !wanted.isEmpty,
              let match = Self.allCases.first(where: { [$0.rawValue, "\($0)", $0.title].contains { key($0) == wanted } })
        else { return nil }
        self = match
    }

    public init(from decoder: Decoder) throws {
        let name = try decoder.singleValueContainer().decode(String.self)
        guard let icon = StickerIcon(named: name) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unknown icon \"\(name)\". Run `labelbridge sticker icons` for the list."))
        }
        self = icon
    }
}

/// Coded as `{"text": "Kitchen"}` or `{"icon": "microwave"}`.
/// Drafts saved by LabelBridge 1.0.2–1.0.3 used `{"text": {"_0": "Kitchen"}}`, which still decodes.
public enum StickerContent: Hashable, Sendable {
    case text(String), icon(StickerIcon)
}

extension StickerContent: Codable {
    private enum Keys: String, CodingKey { case text, icon }
    private enum Legacy: String, CodingKey { case _0 }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if c.contains(.text) && c.contains(.icon) {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: #"An object's content has both "text" and "icon"; use one per object."#))
        }
        if c.contains(.text) {
            if let text = try? c.decode(String.self, forKey: .text) { self = .text(text); return }
            self = .text(try c.nestedContainer(keyedBy: Legacy.self, forKey: .text).decode(String.self, forKey: ._0))
        } else if c.contains(.icon) {
            if (try? c.decode(String.self, forKey: .icon)) != nil { self = .icon(try c.decode(StickerIcon.self, forKey: .icon)); return }
            self = .icon(try c.nestedContainer(keyedBy: Legacy.self, forKey: .icon).decode(StickerIcon.self, forKey: ._0))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: #"An object's content must be {"text": "…"} or {"icon": "…"}."#))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let text): try c.encode(text, forKey: .text)
        case .icon(let icon): try c.encode(icon, forKey: .icon)
        }
    }
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

    private enum CodingKeys: String, CodingKey { case id, content, frame, style }

    /// `id` and `style` are optional so design files can be written by hand.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try c.decode(StickerContent.self, forKey: .content)
        frame = try c.decode(StickerFrame.self, forKey: .frame)
        style = try c.decodeIfPresent(TextStyle.self, forKey: .style) ?? TextStyle()
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

    /// The text objects, in the order of the designer's Objects list.
    public var textSlots: [String] {
        objects.compactMap { if case .text(let text) = $0.content { return text } else { return nil } }
    }

    /// A warning when some text objects keep the design's own text because fewer texts were given.
    public func unfilledTextWarning(given: Int) -> String? {
        let slots = textSlots
        guard given > 0, given < slots.count else { return nil }
        let kept = slots.dropFirst(given).map { "\"\($0.replacingOccurrences(of: "\n", with: "\\n"))\"" }.joined(separator: ", ")
        return "The design has \(slots.count) text objects but \(given) --text \(given == 1 ? "was" : "were") given; the rest keep their text: \(kept)."
    }

    /// Replaces the text of the first `texts.count` text objects, in order; the rest keep their text.
    public func fillingText(_ texts: [String]) throws -> StickerDesign {
        let slots = objects.indices.filter { if case .text = objects[$0].content { return true } else { return false } }
        guard texts.count <= slots.count else {
            throw StickerDesignError.tooManyTexts(given: texts.count, slots: slots.count)
        }
        var filled = self
        for (index, text) in zip(slots, texts) { filled.objects[index].content = .text(text) }
        return filled
    }

    public func validate() throws {
        guard size.widthMM.isFinite, size.lengthMM.isFinite,
              (4...200).contains(size.widthMM), (4...200).contains(size.lengthMM),
              size.widthMM <= size.lengthMM,
              shape != .twoCircles || size == LabelSize(14, 28),
              objects.count <= 100 else {
            throw StickerDesignError.invalidGeometry
        }
        guard Set(objects.map(\.id)).count == objects.count else { throw StickerDesignError.duplicateIDs }
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
    case invalidGeometry, unavailableIcon(String), tooManyTexts(given: Int, slots: Int), empty, duplicateIDs

    public var errorDescription: String? {
        switch self {
        case .invalidGeometry: return "The design has invalid dimensions. Keep objects inside the label and use at most 100 objects."
        case .unavailableIcon(let title): return "The \(title) icon is unavailable on this version of macOS. Choose another icon."
        case .tooManyTexts(let given, let slots):
            return "Got \(given) texts, but the design has \(slots) text \(slots == 1 ? "object" : "objects")."
        case .empty: return "The design is empty. Add text or an icon first."
        case .duplicateIDs: return "Two objects in the design have the same \"id\". Give each object its own id, or leave the ids out."
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

    /// Guides for checking where the printer puts ink on a roll: for paired circles, a 11 mm ring and a
    /// cross at each circle's centre, with a dot in the left circle so the print can be held the way
    /// the designer shows it. For rectangles, a cross at the centre and an outline around the printable
    /// area: 1 mm in from each end, and the edges of the 12 mm print band.
    public static func alignmentTest(size: LabelSize, shape: StickerShape) -> Bitmap {
        let scale = LabelSize.dpi / 25.4
        let (width, height) = size.canvasPixels
        let bandTop = (Int((size.widthMM * scale).rounded()) - height) / 2
        let line = 0.3, centreY = size.widthMM / 2
        var pixels = [Bool](repeating: false, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                let x = (Double(column) + 0.5) / scale, y = (Double(row + bandTop) + 0.5) / scale
                var ink = false
                if shape == .twoCircles {
                    let cx = x < size.lengthMM / 2 ? size.widthMM / 2 : size.lengthMM - size.widthMM / 2
                    let distance = ((x - cx) * (x - cx) + (y - centreY) * (y - centreY)).squareRoot()
                    let ring = abs(distance - 5.5) <= line / 2
                    let cross = (abs(x - cx) <= line / 2 && abs(y - centreY) <= 1.5) || (abs(y - centreY) <= line / 2 && abs(x - cx) <= 1.5)
                    let dot = cx < size.lengthMM / 2 && (x - cx) * (x - cx) + (y - centreY + 3) * (y - centreY + 3) <= 0.36
                    ink = ring || cross || dot
                } else {
                    // The printable area: 1 mm in from each end, and the print band (or the label, if narrower).
                    let top = max(Double(bandTop) / scale, 0) + line / 2
                    let bottom = min(Double(bandTop + height) / scale, size.widthMM) - line / 2
                    let left = 1.0, right = size.lengthMM - 1
                    let inside = x >= left - line / 2 && x <= right + line / 2 && y >= top - line / 2 && y <= bottom + line / 2
                    let edge = abs(x - left) <= line / 2 || abs(x - right) <= line / 2 || abs(y - top) <= line / 2 || abs(y - bottom) <= line / 2
                    let cx = size.lengthMM / 2
                    let cross = (abs(x - cx) <= line / 2 && abs(y - centreY) <= 1.5) || (abs(y - centreY) <= line / 2 && abs(x - cx) <= 1.5)
                    ink = (inside && edge) || cross
                }
                pixels[row * width + column] = ink
            }
        }
        return Bitmap(width: width, height: height, pixels: pixels)
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

/// Moves printed ink to correct a printer or roll that prints off-centre (millimetres; +x toward the
/// label's right end as the designer shows it, +y downward). Applied when printing, never in previews.
public struct StickerOffset: Codable, Hashable, Sendable {
    public static let range = -3.0...3.0
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) {
        self.x = min(max(x, Self.range.lowerBound), Self.range.upperBound)
        self.y = min(max(y, Self.range.lowerBound), Self.range.upperBound)
    }
}

/// A sticker design printed `settings.copies` times (CLI → app, and the designer window).
public struct StickerJob: Codable, Sendable {
    public var design: StickerDesign
    public var settings: PrintSettings
    public var source: JobSource
    /// Print alignment guides for the design's paper instead of its objects.
    public var alignmentTest: Bool

    public init(design: StickerDesign, settings: PrintSettings, source: JobSource, alignmentTest: Bool = false) {
        self.design = design
        self.settings = settings
        self.source = source
        self.alignmentTest = alignmentTest
    }

    private enum CodingKeys: String, CodingKey { case design, settings, source, alignmentTest }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        design = try c.decode(StickerDesign.self, forKey: .design)
        settings = try c.decode(PrintSettings.self, forKey: .settings)
        source = try c.decode(JobSource.self, forKey: .source)
        alignmentTest = try c.decodeIfPresent(Bool.self, forKey: .alignmentTest) ?? false
    }

    /// The bitmap to print (offset applied) and the renderer's warnings.
    public func render(offset: StickerOffset = StickerOffset()) throws -> (bitmap: Bitmap, warnings: [String]) {
        let base: Bitmap, warnings: [String]
        if alignmentTest {
            try design.validate()
            (base, warnings) = (StickerDesignRenderer.alignmentTest(size: design.size, shape: design.shape), [])
        } else {
            guard design.objects.contains(where: \.hasContent) else { throw StickerDesignError.empty }
            let rendered = try StickerDesignRenderer.render(design)
            (base, warnings) = (rendered.bitmap, rendered.warning?.components(separatedBy: "\n") ?? [])
        }
        let scale = LabelSize.dpi / 25.4
        let shifted = base.shifted(dx: Int((offset.x * scale).rounded()), dy: Int((offset.y * scale).rounded()))
        guard shifted.inkCount < base.inkCount else { return (shifted, warnings) }
        let side = offset.y != 0 ? "the 12 mm print band" : "the label"
        return (shifted, warnings + ["The print offset (\(Self.mm(offset.x)) right, \(Self.mm(offset.y)) down) moves some ink outside \(side), so it won't print."])
    }

    private static func mm(_ v: Double) -> String { "\(v.formatted(.number.precision(.fractionLength(0...2)))) mm" }
}

/// The designer's saved templates and draft, as stored in LabelBridge's preferences, plus design files.
public enum StickerLibrary {
    public static let draftKey = "stickerDesign"
    public static let templatesKey = "stickerTemplates"
    /// Names that select the designer's current draft.
    public static let draftNames: Set<String> = ["draft", "current"]

    public static func savedTemplates(_ defaults: UserDefaults?) throws -> [StickerTemplate] {
        guard let data = defaults?.data(forKey: templatesKey) else { return [] }
        do { return try JSONDecoder().decode([StickerTemplate].self, from: data) }
        catch { throw StickerLibraryError.unreadableTemplates(describe(error)) }
    }

    /// The designer's draft; nil when there is none, an error when it can't be read.
    public static func draft(_ defaults: UserDefaults?) throws -> StickerDesign? {
        guard let data = defaults?.data(forKey: draftKey) else { return nil }
        do { return try JSONDecoder().decode(StickerDesign.self, from: data) }
        catch { throw StickerLibraryError.unreadableDraft(describe(error)) }
    }

    /// True for arguments that name a design file rather than a template: a .json path or any path with a `/`.
    public static func isFilePath(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.lowercased().hasSuffix(".json") || n.contains("/") || n.hasPrefix("~")
    }

    /// Finds a design. Order: a design file (`*.json`, or a path containing `/`); your saved templates by
    /// name (any capitalisation; the most recently saved wins) or id; `draft`/`current`; built-in templates
    /// by name or id. A template name that looks like a path can still be printed by its id.
    public static func resolve(_ name: String, defaults: UserDefaults?) throws -> (name: String, design: StickerDesign) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFilePath(trimmed) { return try load(file: trimmed) }
        let key = trimmed.lowercased()
        let savedResult = Result { try savedTemplates(defaults) }
        let saved = ((try? savedResult.get()) ?? []).reversed()         // newest first
        if let match = saved.first(where: { $0.name.lowercased() == key }) ?? saved.first(where: { $0.id == trimmed }) {
            try match.design.validate()
            return (match.name, match.design)
        }
        if draftNames.contains(key) {
            guard let design = try draft(defaults) else { throw StickerLibraryError.noDraft }
            try design.validate()
            return ("Draft", design)
        }
        let builtIn = StickerTemplate.builtIn
        if let match = builtIn.first(where: { $0.name.lowercased() == key || $0.id.lowercased() == key }) {
            return (match.name, match.design)
        }
        if case .failure(let error) = savedResult { throw error }      // it may have been one of those
        throw StickerLibraryError.notFound(trimmed, saved.reversed().map(\.name) + builtIn.map(\.name))
    }

    private static func load(file: String) throws -> (name: String, design: StickerDesign) {
        let path = (file as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let data = FileManager.default.contents(atPath: path) else {
            throw StickerLibraryError.unreadableFile(file, "there's no readable file at that path")
        }
        let design: StickerDesign
        do {
            // A template file ({id, name, design}) or a bare design; report errors for the form it is.
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["design"] != nil { design = try JSONDecoder().decode(StickerTemplate.self, from: data).design }
            else { design = try JSONDecoder().decode(StickerDesign.self, from: data) }
        } catch { throw StickerLibraryError.unreadableFile(file, describe(error)) }
        try design.validate()
        return ((file as NSString).lastPathComponent, design)
    }

    /// Pretty JSON for a design, in the form `resolve` and the app read back.
    public static func export(_ design: StickerDesign) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(design)
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let c): return c.debugDescription
        case DecodingError.keyNotFound(let key, let c):
            return "missing \"\(key.stringValue)\"" + (c.codingPath.isEmpty ? "" : " in \(c.codingPath.map(\.stringValue).joined(separator: "."))")
        case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c):
            return "wrong value at \(c.codingPath.map(\.stringValue).joined(separator: "."))"
        default: return error.localizedDescription
        }
    }
}

public enum StickerLibraryError: LocalizedError {
    case notFound(String, [String]), noDraft, unreadableFile(String, String), unreadableDraft(String), unreadableTemplates(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name, let names):
            return "No template named \"\(name)\". Available: \(names.joined(separator: ", ")). Or use draft, or a .json design file."
        case .noDraft: return "There is no designer draft yet. Open the sticker designer in LabelBridge (version 1.0.5 or later) first."
        case .unreadableTemplates(let reason):
            return "Can't read your saved sticker templates: \(reason.hasSuffix(".") ? String(reason.dropLast()) : reason). Built-in templates and .json files still work."
        case .unreadableDraft(let reason):
            return "Can't read the sticker designer's draft: \(reason.hasSuffix(".") ? String(reason.dropLast()) : reason). Open the designer and pick a template to replace it."
        case .unreadableFile(let path, let reason):
            return "Can't read the design in \(path): \(reason.hasSuffix(".") ? String(reason.dropLast()) : reason)."
        }
    }
}
