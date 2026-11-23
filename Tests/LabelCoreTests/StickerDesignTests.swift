import XCTest
@testable import LabelCore

final class StickerDesignTests: XCTestCase {
    func testBlankTemplateDoesNotPrintCircleOutlines() throws {
        let design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles)
        let result = try StickerDesignRenderer.render(design)
        XCTAssertFalse(hasInk(result.bitmap, columns: 0..<result.bitmap.width))
        XCTAssertNil(result.warning)
    }

    func testIndependentIconAndTextStayInTheirOwnCircles() throws {
        let design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles, objects: [
            StickerObject(content: .icon(.home), frame: .init(x: 3, y: 3, width: 8, height: 8)),
            StickerObject(content: .text("Light"), frame: .init(x: 16, y: 5, width: 10, height: 4)),
        ])
        let result = try StickerDesignRenderer.render(design)
        XCTAssertNil(result.warning)
        let bitmap = PrinterProfile.d110.prepare(result.bitmap)
        XCTAssertEqual(bitmap.width, 224)
        XCTAssertEqual(bitmap.height, 96)
        XCTAssertTrue(hasInk(bitmap, columns: 0..<112))
        XCTAssertTrue(hasInk(bitmap, columns: 112..<224))
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap.isBlack(x: x, y: y) {
                let centerX = x < 112 ? 56.0 : 168.0
                XCTAssertLessThan(pow(Double(x) - centerX, 2) + pow(Double(y) - 48, 2), 56 * 56)
            }
        }
    }

    func testMovingAnObjectToTheOtherCircleLeavesFirstCircleEmpty() throws {
        var design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles, objects: [
            StickerObject(content: .icon(.home), frame: .init(x: 3, y: 3, width: 8, height: 8)),
        ])
        let first = try StickerDesignRenderer.render(design).bitmap
        XCTAssertTrue(hasInk(first, columns: 0..<165))
        XCTAssertFalse(hasInk(first, columns: 166..<331))
        design.objects[0].frame.x += 14
        let moved = try StickerDesignRenderer.render(design).bitmap
        XCTAssertFalse(hasInk(moved, columns: 0..<165))
        XCTAssertTrue(hasInk(moved, columns: 166..<331))
    }

    func testInkOutsideThePrintBandProducesAWarning() throws {
        let design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles, objects: [
            StickerObject(content: .icon(.home), frame: .init(x: 0, y: 0, width: 14, height: 14)),
        ])
        let result = try StickerDesignRenderer.render(design)
        XCTAssertTrue(result.warning?.contains("print band") == true, result.warning ?? "")
        XCTAssertTrue(hasInk(result.bitmap, columns: 0..<165))
    }

    func testDesignRoundTripPreservesObjectsAndTypography() throws {
        var design = StickerTemplate.builtIn[1].design
        design.objects[1].content = .text("שלום")
        design.objects[1].style = TextStyle(bold: true, alignment: .trailing, italic: true, fontSizePoints: 6)
        let decoded = try JSONDecoder().decode(StickerDesign.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(decoded, design)
        XCTAssertEqual(try StickerDesignRenderer.render(decoded).bitmap, try StickerDesignRenderer.render(design).bitmap)
    }

    func testEditingTextChangesOnlyThatObjectsInk() throws {
        var design = StickerTemplate.builtIn[2].design
        let before = try StickerDesignRenderer.render(design).bitmap
        design.objects[0].content = .text("Kitchen")
        let after = try StickerDesignRenderer.render(design).bitmap
        XCTAssertNotEqual(before, after)
        for y in 0..<before.height {
            for x in 166..<before.width {
                XCTAssertEqual(before.isBlack(x: x, y: y), after.isBlack(x: x, y: y))
            }
        }
    }

    func testFixedPointSizeDoesNotGrowWhenObjectGetsTaller() throws {
        var design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles, objects: [
            StickerObject(content: .text("Hi"), frame: .init(x: 2, y: 4.5, width: 10, height: 3),
                          style: TextStyle(fontSizePoints: 6)),
        ])
        let small = try StickerDesignRenderer.render(design).bitmap
        design.objects[0].frame.y = 2
        design.objects[0].frame.height = 8
        let tall = try StickerDesignRenderer.render(design).bitmap
        XCTAssertGreaterThan(inkHeight(small), 0)
        XCTAssertEqual(inkHeight(small), inkHeight(tall))
        design.objects[0].style.fontSizePoints = 10
        let larger = try StickerDesignRenderer.render(design).bitmap
        XCTAssertGreaterThan(inkHeight(larger), inkHeight(tall))
    }

    func testOlderStylesKeepAutomaticSizingAndNoItalic() throws {
        let style = try JSONDecoder().decode(TextStyle.self, from: Data(#"{"bold":true,"alignment":"center"}"#.utf8))
        XCTAssertEqual(style, TextStyle(bold: true))
    }

    func testOversizedTextWarnsAndInvalidFontSizesAreRejected() throws {
        var design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles, objects: [
            StickerObject(content: .text("Kitchen"), frame: .init(x: 2, y: 5, width: 10, height: 3),
                          style: TextStyle(fontSizePoints: 48)),
        ])
        XCTAssertTrue(try StickerDesignRenderer.render(design).warning?.contains("text does not fit") == true)
        for points in [Double.nan, 0, 100] {
            design.objects[0].style.fontSizePoints = points
            XCTAssertThrowsError(try StickerDesignRenderer.render(design))
        }
    }

    func testInvalidGeometryIsRejectedBeforeRendering() {
        for frame in [
            StickerFrame(x: .nan, y: 0, width: 8, height: 8),
            StickerFrame(x: 27, y: 0, width: 8, height: 8),
            StickerFrame(x: 0, y: 0, width: 0, height: 8),
        ] {
            let design = StickerDesign(size: LabelSize(14, 28), shape: .twoCircles, objects: [
                StickerObject(content: .icon(.home), frame: frame),
            ])
            XCTAssertThrowsError(try StickerDesignRenderer.render(design))
        }
    }

    private func hasInk(_ bitmap: Bitmap, columns: Range<Int>) -> Bool {
        for y in 0..<bitmap.height {
            for x in columns where bitmap.isBlack(x: x, y: y) { return true }
        }
        return false
    }

    private func inkHeight(_ bitmap: Bitmap) -> Int {
        let rows = (0..<bitmap.height).filter { y in
            (0..<bitmap.width).contains { x in bitmap.isBlack(x: x, y: y) }
        }
        guard let first = rows.first, let last = rows.last else { return 0 }
        return last - first + 1
    }
}
