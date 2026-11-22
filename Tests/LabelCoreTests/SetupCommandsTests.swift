import XCTest
@testable import LabelCore

final class SetupCommandsTests: XCTestCase {
    func testQueueArguments() {
        let args = SetupCommands.addQueueArguments(ppdPath: "/Applications/LabelBridge.app/Contents/Resources/NIIMBOT_D11.ppd")
        XCTAssertEqual(Array(args.prefix(2)), ["-p", "NIIMBOT_D11"])
        XCTAssertTrue(args.contains("socket://127.0.0.1:9183"))
        XCTAssertTrue(args.contains("NIIMBOT D11 (Bluetooth)"))
        XCTAssertTrue(args.contains("-E"))
        XCTAssertTrue(args.contains("printer-is-shared=false"))
    }

    func testSymlinkCommandQuotesPaths() {
        let cmd = SetupCommands.installCLICommand(helperPath: "/Applications/Label Bridge's.app/Contents/Helpers/labelbridge")
        XCTAssertEqual(cmd, "mkdir -p '/usr/local/bin' && ln -sf '/Applications/Label Bridge'\\''s.app/Contents/Helpers/labelbridge' '/usr/local/bin/labelbridge'")
    }

    func testIsInApplications() {
        XCTAssertTrue(SetupCommands.isInApplications("/Applications/LabelBridge.app"))
        XCTAssertFalse(SetupCommands.isInApplications("/Volumes/LabelBridge/LabelBridge.app"))
        XCTAssertFalse(SetupCommands.isInApplications("/private/var/folders/x/AppTranslocation/ABC/d/LabelBridge.app"))
    }
}
