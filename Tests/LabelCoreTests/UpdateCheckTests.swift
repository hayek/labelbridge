import XCTest
@testable import LabelCore

final class UpdateCheckTests: XCTestCase {
    func testNewerVersionsCompareNumerically() {
        XCTAssertTrue(UpdateCheck.isNewer("v1.1", than: "1.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(UpdateCheck.isNewer("v2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.0", than: "1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("v1.0.0", than: "1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("v0.9", than: "1.0"))
        XCTAssertFalse(UpdateCheck.isNewer("nightly", than: "1.0"))
    }

    func testParsesLatestReleaseFromGitHub() throws {
        let json = """
        {"tag_name":"v1.1","name":"LabelBridge 1.1","html_url":"https://github.com/hayek/labelbridge/releases/tag/v1.1",
         "draft":false,"prerelease":false,
         "assets":[{"name":"LabelBridge.dmg","browser_download_url":"https://github.com/hayek/labelbridge/releases/download/v1.1/LabelBridge.dmg"}]}
        """
        let r = try UpdateCheck.parseLatest(Data(json.utf8))
        XCTAssertEqual(r.version, "1.1")
        XCTAssertEqual(r.page.absoluteString, "https://github.com/hayek/labelbridge/releases/tag/v1.1")
        XCTAssertEqual(r.download?.lastPathComponent, "LabelBridge.dmg")
    }
}
