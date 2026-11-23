import XCTest
@testable import LabelCore

/// The pieces `labelbridge sticker` is built from: finding designs, filling text, design files,
/// sticker jobs over IPC, the alignment test and the print offset.
final class StickerCLITests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "lb-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testResolvesBuiltInTemplatesByIdOrNameAndPrefersSavedTemplates() throws {
        let d = defaults()
        XCTAssertEqual(try StickerLibrary.resolve("names", defaults: d).name, "Names")
        XCTAssertEqual(try StickerLibrary.resolve("ICONS + TEXT", defaults: d).name, "Icons + text")
        let mine = StickerTemplate(name: "Names", design: StickerTemplate.builtIn[0].design)
        d.set(try JSONEncoder().encode([mine]), forKey: StickerLibrary.templatesKey)
        XCTAssertEqual(try StickerLibrary.resolve("Names", defaults: d).design, mine.design)
        XCTAssertThrowsError(try StickerLibrary.resolve("Nope", defaults: d)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Blank circles"))
        }
    }

    func testDraftIsTheDesignersSavedDraft() throws {
        let d = defaults()
        XCTAssertThrowsError(try StickerLibrary.resolve("draft", defaults: d))
        let draft = StickerTemplate.builtIn[2].design
        d.set(try JSONEncoder().encode(draft), forKey: StickerLibrary.draftKey)
        XCTAssertEqual(try StickerLibrary.resolve("draft", defaults: d).design, draft)
    }

    func testTextFillsTextObjectsInOrderAndRejectsExtras() throws {
        let design = StickerTemplate.builtIn[1].design          // microwave, "Kitchen", lamp, "Light"
        XCTAssertEqual(try design.fillingText(["Oven"]).textSlots, ["Oven", "Light"])
        XCTAssertEqual(try design.fillingText(["Oven", "Hall"]).textSlots, ["Oven", "Hall"])
        XCTAssertThrowsError(try design.fillingText(["a", "b", "c"]))
    }

    func testHandWrittenDesignFileDecodes() throws {
        let json = #"""
        {"size": {"widthMM": 14, "lengthMM": 28}, "shape": "twoCircles", "objects": [
          {"content": {"icon": "Light bulb"}, "frame": {"x": 3, "y": 3, "width": 8, "height": 8}},
          {"content": {"text": "Hall"}, "frame": {"x": 16, "y": 5, "width": 10, "height": 4}, "style": {"bold": true}}]}
        """#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lb-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let design = try StickerLibrary.resolve(url.path, defaults: defaults()).design
        XCTAssertEqual(design.objects[0].content, .icon(.lightbulb))
        XCTAssertEqual(design.objects[1].style, TextStyle(bold: true))
        XCTAssertNoThrow(try StickerDesignRenderer.render(design))
    }

    func testExportRoundTripsAndUsesReadableContent() throws {
        let design = StickerTemplate.builtIn[1].design
        let data = try StickerLibrary.export(design)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""text" : "Kitchen""#), text)
        XCTAssertTrue(text.contains(#""icon" : "microwave""#), text)
        XCTAssertEqual(try JSONDecoder().decode(StickerDesign.self, from: data), design)
    }

    func testDraftsSavedByEarlierVersionsStillDecode() throws {
        let old = #"{"content":{"text":{"_0":"Kitchen"}},"frame":{"x":2,"y":9,"width":10,"height":3},"id":"4E50E99C-8077-4237-8EA5-900CD6AB848B","style":{"alignment":"center","bold":false}}"#
        let icon = #"{"content":{"icon":{"_0":"lamp.ceiling"}},"frame":{"x":2,"y":2,"width":8,"height":8},"id":"5E50E99C-8077-4237-8EA5-900CD6AB848B","style":{"alignment":"center","bold":false}}"#
        XCTAssertEqual(try JSONDecoder().decode(StickerObject.self, from: Data(old.utf8)).content, .text("Kitchen"))
        XCTAssertEqual(try JSONDecoder().decode(StickerObject.self, from: Data(icon.utf8)).content, .icon(.ceilingLight))
    }

    func testStickerJobSurvivesIPC() throws {
        let job = StickerJob(design: StickerTemplate.builtIn[2].design, settings: PrintSettings(copies: 2, media: .transparent), source: .cli)
        guard case .printSticker(let decoded) = try IPCCoding.decode(IPCRequest.self, from: IPCCoding.encode(IPCRequest.printSticker(job))) else {
            return XCTFail()
        }
        XCTAssertEqual(decoded.design, job.design)
        XCTAssertEqual(decoded.settings, job.settings)
        XCTAssertFalse(decoded.alignmentTest)
    }

    func testEmptyDesignIsRejectedButItsAlignmentTestPrints() throws {
        let blank = StickerJob(design: StickerTemplate.builtIn[3].design, settings: PrintSettings(), source: .cli)
        XCTAssertThrowsError(try blank.render())
        var test = blank
        test.alignmentTest = true
        let bitmap = try test.render().bitmap
        // Ring and cross centred in each circle: ink at both centres (columns ~83 and ~248, row 71).
        XCTAssertTrue(bitmap.isBlack(x: 83, y: 71))
        XCTAssertTrue(bitmap.isBlack(x: 248, y: 71))
        // The ring (radius 5.5 mm = 65 px) crosses the horizontal centre line on both sides.
        XCTAssertTrue((-2...2).contains { bitmap.isBlack(x: 83 - 65 + $0, y: 71) })
        XCTAssertTrue((-2...2).contains { bitmap.isBlack(x: 248 + 65 + $0, y: 71) })
    }

    func testOffsetMovesInkByMillimetres() throws {
        let job = StickerJob(design: StickerTemplate.builtIn[3].design, settings: PrintSettings(), source: .cli, alignmentTest: true)
        let plain = try job.render().bitmap
        let moved = try job.render(offset: StickerOffset(x: 1, y: -0.5)).bitmap
        let dx = 12, dy = -6                                     // 1 mm and 0.5 mm at 300 dpi
        for y in 10..<(plain.height - 10) {
            for x in 20..<(plain.width - 20) { XCTAssertEqual(moved.isBlack(x: x + dx, y: y + dy), plain.isBlack(x: x, y: y)) }
        }
        XCTAssertEqual(StickerOffset(x: 9, y: -9), StickerOffset(x: 3, y: -3))
    }

    // MARK: Review fixes (1.0.5)

    func testNewestSavedTemplateWinsAndCapitalisationDoesNotMatter() throws {
        let d = defaults()
        let old = StickerTemplate(name: "Names", design: StickerTemplate.builtIn[0].design)
        let new = StickerTemplate(name: "Names", design: StickerTemplate.builtIn[1].design)
        d.set(try JSONEncoder().encode([old, new]), forKey: StickerLibrary.templatesKey)
        XCTAssertEqual(try StickerLibrary.resolve("Names", defaults: d).design, new.design)
        XCTAssertEqual(try StickerLibrary.resolve("names", defaults: d).design, new.design, "lowercase must not pick the built-in")
        XCTAssertEqual(try StickerLibrary.resolve(old.id, defaults: d).design, old.design, "an id picks that exact template")
    }

    func testFilesAreOnlyUsedForJsonOrPathArguments() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("names"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let previous = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(dir.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previous) }
        XCTAssertEqual(try StickerLibrary.resolve("Names", defaults: defaults()).name, "Names")
        XCTAssertTrue(StickerLibrary.isFilePath("kitchen.json"))
        XCTAssertTrue(StickerLibrary.isFilePath("./kitchen"))
        XCTAssertFalse(StickerLibrary.isFilePath("Icons + text"))
    }

    func testSavedTemplateNamedDraftWinsOverTheDraft() throws {
        let d = defaults()
        let mine = StickerTemplate(name: "Draft", design: StickerTemplate.builtIn[0].design)
        d.set(try JSONEncoder().encode([mine]), forKey: StickerLibrary.templatesKey)
        d.set(try JSONEncoder().encode(StickerTemplate.builtIn[2].design), forKey: StickerLibrary.draftKey)
        XCTAssertEqual(try StickerLibrary.resolve("draft", defaults: d).design, mine.design)
    }

    func testUnreadableDraftAndTemplatesSayWhat() throws {
        let d = defaults()
        d.set(Data("{}".utf8), forKey: StickerLibrary.draftKey)
        XCTAssertThrowsError(try StickerLibrary.resolve("draft", defaults: d)) { XCTAssertTrue($0.localizedDescription.contains("Can't read the sticker designer's draft"), $0.localizedDescription) }
        d.set(Data("[1]".utf8), forKey: StickerLibrary.templatesKey)
        XCTAssertEqual(try StickerLibrary.resolve("Names", defaults: d).name, "Names", "built-ins still work")
        XCTAssertThrowsError(try StickerLibrary.resolve("My thing", defaults: d)) { XCTAssertTrue($0.localizedDescription.contains("saved sticker templates"), $0.localizedDescription) }
    }

    func testUnfilledTextWarning() {
        let design = StickerTemplate.builtIn[2].design          // "Label 1", "Label 2"
        XCTAssertNil(design.unfilledTextWarning(given: 0))
        XCTAssertNil(design.unfilledTextWarning(given: 2))
        XCTAssertTrue(design.unfilledTextWarning(given: 1)?.contains("\"Label 2\"") == true)
    }

    func testOffsetThatPushesInkOffTheBandWarns() throws {
        let job = StickerJob(design: StickerTemplate.builtIn[3].design, settings: PrintSettings(), source: .cli, alignmentTest: true)
        XCTAssertTrue(try job.render(offset: StickerOffset(x: 0.25)).warnings.isEmpty)
        let down = try job.render(offset: StickerOffset(y: 1)).warnings
        XCTAssertEqual(down.count, 1)
        XCTAssertTrue(down[0].contains("12 mm print band"), down[0])
    }

    func testDuplicateIdsAndSwappedSizesInDesignFiles() throws {
        let id = UUID().uuidString
        let dup = #"{"size":{"widthMM":28,"lengthMM":14},"shape":"twoCircles","objects":[{"id":"\#(id)","content":{"text":"A"},"frame":{"x":2,"y":4,"width":10,"height":4}},{"id":"\#(id)","content":{"text":"B"},"frame":{"x":16,"y":4,"width":10,"height":4}}]}"#
        let design = try JSONDecoder().decode(StickerDesign.self, from: Data(dup.utf8))
        XCTAssertEqual(design.size, LabelSize(14, 28), "width and length are normalised like LabelSize.init")
        XCTAssertThrowsError(try design.validate()) { XCTAssertTrue($0.localizedDescription.contains("same \"id\""), $0.localizedDescription) }
    }

    func testRectangleAlignmentOutlineSitsInsideThePrintableArea() {
        for size in [LabelSize(15, 50), LabelSize(12, 40), LabelSize(14, 22)] {
            let b = StickerDesignRenderer.alignmentTest(size: size, shape: .rectangle)
            let rows = (0..<b.height).filter { y in (0..<b.width).contains { b.isBlack(x: $0, y: y) } }
            XCTAssertEqual(rows.first, 0, "top edge of the printable band, \(size)")
            XCTAssertEqual(rows.last, b.height - 1, "bottom edge of the printable band, \(size)")
            let mid = b.height / 2
            let columns = (0..<b.width).filter { b.isBlack(x: $0, y: mid) }
            XCTAssertEqual(Double(columns.first!), 1 * LabelSize.dpi / 25.4, accuracy: 3, "1 mm from the left end, \(size)")
        }
    }
}
