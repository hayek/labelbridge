import XCTest
@testable import LabelCore

final class RowEncoderTests: XCTestCase {
    private func bitmap(width: Int, height: Int = 142, black: (Int, Int) -> Bool) -> Bitmap {
        var px = [Bool](repeating: false, count: width * height)
        for y in 0..<height { for x in 0..<width { px[y * width + x] = black(x, y) } }
        return Bitmap(width: width, height: height, pixels: px)
    }

    private func rowPackets(_ page: EncodedPage) -> [Packet] { page.packets.filter { $0.cmd == Cmd.bitmapRow.rawValue } }

    func testRotationMapping() {
        let page = RowEncoder.encode(bitmap(width: 10) { x, y in x == 2 && y == 141 })
        let row = rowPackets(page).first!
        XCTAssertEqual(Array(row.data[0..<2]), [0, 2])     // pos 2
        XCTAssertEqual(row.data[6], 0x80)                    // first image byte, MSB = col 0
        XCTAssertEqual(row.data[5], 1)                       // repeats
    }

    func testColsPaddedTo144() {
        let page = RowEncoder.encode(bitmap(width: 10) { _, _ in false })
        XCTAssertEqual(page.cols, 144)
        XCTAssertEqual(page.rows, 10)
    }

    func testRunsCompressRepeats() {
        let rows = rowPackets(RowEncoder.encode(bitmap(width: 300) { _, y in y < 8 }))
        XCTAssertEqual(rows.map { $0.data[5] }, [255, 45])
        XCTAssertEqual(rows.map { Array($0.data[0..<2]) }, [[0, 0], Packet.u16(255)])
    }

    func testBlankRowsUseEmptyRow() {
        let page = RowEncoder.encode(bitmap(width: 20) { _, _ in false })
        XCTAssertEqual(page.packets.map(\.cmd), [Cmd.emptyRow.rawValue])
        XCTAssertEqual(page.packets.first?.data, [0, 0, 20])
    }

    func testPixelCountTotalMode() {
        let row = rowPackets(RowEncoder.encode(bitmap(width: 1) { _, _ in true })).first!
        XCTAssertEqual(Array(row.data[2..<5]), [0, 142, 0])
        XCTAssertEqual(row.data.count, 6 + 18)
    }
}
