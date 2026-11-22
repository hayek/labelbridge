import XCTest
import AppKit
@testable import LabelCore

final class PDFLabelsTests: XCTestCase {
    private func pdf(pages: Int) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 141.73, height: 42.52)     // 50 × 15 mm, landscape
        let ctx = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for p in 1...pages {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            ("Label \(p)" as NSString).draw(at: CGPoint(x: 10, y: 8), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 22)])
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    func testTwoPagePDFGivesTwoLabels() throws {
        let bitmaps = try PDFLabels.bitmaps(from: pdf(pages: 2), size: .defaultSize)
        XCTAssertEqual(bitmaps.count, 2)
        for b in bitmaps {
            XCTAssertEqual(b.width, 591); XCTAssertEqual(b.height, 142)
            var inked = 0, inMargin = 0
            for y in 0..<b.height { for x in 0..<b.width where b.isBlack(x: x, y: y) { inked += 1; if x < 24 || x >= 567 { inMargin += 1 } } }
            XCTAssertGreaterThan(inked, 100)
            XCTAssertEqual(inMargin, 0)
        }
    }

    func testLabelSizeComesFromThePage() {
        XCTAssertEqual(PDFLabels.labelSize(of: pdf(pages: 1)), LabelSize(15, 50))
    }

    func testRejectsNonPDF() {
        XCTAssertThrowsError(try PDFLabels.bitmaps(from: Data("POST / HTTP/1.1\r\n".utf8), size: .defaultSize))
    }
}
