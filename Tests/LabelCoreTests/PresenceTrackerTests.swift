import XCTest
@testable import LabelCore

final class PresenceTrackerTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1000)

    func testNothingSeenMeansAbsent() {
        XCTAssertNil(PresenceTracker(timeout: 6).current(at: t0))
    }

    func testRecentlySeenPrinterIsPresent() {
        var p = PresenceTracker(timeout: 6)
        p.saw("D11_H-1234", at: t0)
        XCTAssertEqual(p.current(at: t0.addingTimeInterval(5)), "D11_H-1234")
    }

    func testPrinterGoesAbsentAfterTimeout() {
        var p = PresenceTracker(timeout: 6)
        p.saw("D11_H-1234", at: t0)
        XCTAssertNil(p.current(at: t0.addingTimeInterval(6.5)))
    }
}
