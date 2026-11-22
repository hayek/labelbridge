import XCTest
@testable import LabelCore

final class TextRendererTests: XCTestCase {
    let size = LabelSize.defaultSize
    let center = TextStyle(fontName: nil, bold: false, alignment: .center)

    private func ink(_ b: Bitmap, xs: Range<Int>? = nil, ys: Range<Int>? = nil) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for y in ys ?? 0..<b.height { for x in xs ?? 0..<b.width where b.isBlack(x: x, y: y) { out.append((x, y)) } }
        return out
    }

    private func marginsClean(_ b: Bitmap) -> Bool {
        ink(b, xs: 0..<24).isEmpty && ink(b, xs: (b.width - 24)..<b.width).isEmpty
    }

    func testCanvasFor15x50() {
        XCTAssertEqual(size.canvasPixels.length, 591)
        XCTAssertEqual(size.canvasPixels.height, 142)
    }

    func testParseSize() {
        XCTAssertEqual(LabelSize(parsing: "50x15"), LabelSize(15, 50))
        XCTAssertEqual(LabelSize(parsing: "15x50"), LabelSize(15, 50))
        XCTAssertNil(LabelSize(parsing: "abc"))
    }

    func testBatchSkipsBlankItems() {
        let r = Batch.items(from: "Dana\n\n  \nYossi")
        XCTAssertEqual(r.items, ["Dana", "Yossi"])
        XCTAssertEqual(r.skipped, 2)
    }

    func testEscapedNewline() {
        XCTAssertEqual(Batch.items(from: "Dana\\nCohen").items, ["Dana\nCohen"])
    }

    func testInkStaysInsideEndMargins() {
        let r = TextRenderer.render("WWWWWWWW", size: size, style: center)
        XCTAssertEqual(r.bitmap.width, 591)
        XCTAssertFalse(ink(r.bitmap).isEmpty)
        XCTAssertTrue(marginsClean(r.bitmap))
    }

    func testLongTextTruncatesWithinMargins() {
        let r = TextRenderer.render(String(repeating: "Long name ", count: 20), size: size, style: center)
        XCTAssertNotNil(r.warning)
        XCTAssertTrue(marginsClean(r.bitmap))
    }

    func testMixedScriptsRender() {
        for text in ["דנה 3א", "محمد 12", "東京", "🎉 Party"] {
            let r = TextRenderer.render(text, size: size, style: center)
            XCTAssertFalse(ink(r.bitmap).isEmpty, text)
            XCTAssertNil(r.warning, text)
            XCTAssertTrue(marginsClean(r.bitmap), text)
        }
    }

    func testLeadingAlignmentFollowsRTL() {
        let leading = TextStyle(fontName: nil, bold: false, alignment: .leading)
        func centroidX(_ t: String) -> Double {
            let pts = ink(TextRenderer.render(t, size: size, style: leading).bitmap)
            return Double(pts.reduce(0) { $0 + $1.0 }) / Double(pts.count)
        }
        XCTAssertGreaterThan(centroidX("שלום"), 591 / 2)
        XCTAssertLessThan(centroidX("Hello"), 591 / 2)
    }

    func testTwoLinesUseTwoBands() {
        let b = TextRenderer.render("A\nB", size: size, style: center).bitmap
        XCTAssertFalse(ink(b, ys: 0..<71).isEmpty)
        XCTAssertFalse(ink(b, ys: 71..<142).isEmpty)
    }
}
