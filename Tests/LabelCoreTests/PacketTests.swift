import XCTest
@testable import LabelCore

final class PacketTests: XCTestCase {
    func testDensityPacketBytes() {
        XCTAssertEqual(Packet(cmd: 0x21, data: [3]).bytes(), [0x55, 0x55, 0x21, 0x01, 0x03, 0x23, 0xAA, 0xAA])
    }

    func testConnectHasPrefix() {
        XCTAssertEqual(Packet(cmd: Cmd.connect.rawValue).bytes(), [0x03, 0x55, 0x55, 0xC1, 0x01, 0x01, 0xC1, 0xAA, 0xAA])
    }

    func testExpectedReplies() {
        XCTAssertEqual(Packet.expectedReply(for: .setDensity), 0x31)
        XCTAssertEqual(Packet.expectedReply(for: .printStart), 0x02)
        XCTAssertEqual(Packet.expectedReply(for: .pageEnd), 0xE4)
        XCTAssertEqual(Packet.expectedReply(for: .printStatus), 0xB3)
        XCTAssertNil(Packet.expectedReply(for: .bitmapRow))
    }

    func testU16IsBigEndian() {
        XCTAssertEqual(Packet.u16(591), [0x02, 0x4F])
    }

    func testParserSplitsAndJoinsFrames() {
        var parser = FrameParser()
        let first = parser.feed([0x00, 0x13, 0x55, 0x55, 0x31, 0x01, 0x01, 0x31, 0xAA, 0xAA, 0x55, 0x55])
        let second = parser.feed([0x02, 0x01, 0x01, 0x02, 0xAA, 0xAA])
        XCTAssertEqual(first.map(\.cmd), [0x31])
        XCTAssertEqual(second.map(\.cmd), [0x02])
        XCTAssertEqual(second.first?.data, [0x01])
    }

    func testParserDropsBadChecksum() {
        var parser = FrameParser()
        XCTAssertTrue(parser.feed([0x55, 0x55, 0x31, 0x01, 0x01, 0x99, 0xAA, 0xAA]).isEmpty)
    }
}
