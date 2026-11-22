import XCTest
@testable import LabelCore

final class IPCTests: XCTestCase {
    private let job = LabelJob(items: ["Dana", "דנה", "محمد"], size: .defaultSize, style: TextStyle(),
                               settings: PrintSettings(density: 3, copies: 1), source: .cli)

    func testRequestRoundTrip() throws {
        let data = try IPCCoding.encode(IPCRequest.print(job))
        guard case .print(let decoded) = try IPCCoding.decode(IPCRequest.self, from: data) else { return XCTFail() }
        XCTAssertEqual(decoded.items, ["Dana", "דנה", "محمد"])
        XCTAssertEqual(data.last, UInt8(ascii: "\n"))
        XCTAssertFalse(data.dropLast().contains(UInt8(ascii: "\n")))
    }

    func testServerClientRoundTrip() throws {
        let path = NSTemporaryDirectory() + "lb-\(UUID().uuidString.prefix(8)).sock"
        let server = try IPCServer(path: path) { request, send in
            guard case .print(let j) = request else { return }
            send(.progress(1, j.items.count))
            send(.result(JobResult(ok: true, printed: j.items.count, total: j.items.count)))
        }
        defer { server.stop() }
        var progress: [(Int, Int)] = []
        let final = try IPCClient(path: path).send(.print(job)) { progress.append(($0, $1)) }
        guard case .result(let r) = final else { return XCTFail("expected result") }
        XCTAssertEqual(r.printed, 3)
        XCTAssertEqual(progress.first?.0, 1)
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testClientFailsFastWithoutServer() {
        XCTAssertThrowsError(try IPCClient(path: NSTemporaryDirectory() + "missing.sock").send(.status) { _, _ in })
    }

    func testExitCodes() {
        XCTAssertEqual(ExitCode.for(JobResult(ok: true, printed: 2, total: 2)), 0)
        XCTAssertEqual(ExitCode.for(JobResult(ok: false, printed: 0, total: 0, failure: .badInput)), 2)
        XCTAssertEqual(ExitCode.for(JobResult(ok: false, printed: 0, total: 1, failure: .notFound)), 3)
        XCTAssertEqual(ExitCode.for(JobResult(ok: false, printed: 0, total: 1, failure: .busy)), 3)
        XCTAssertEqual(ExitCode.for(JobResult(ok: false, printed: 1, total: 3, failure: .failedMidJob)), 4)
        XCTAssertEqual(ExitCode.for(JobResult(ok: false, printed: 0, total: 1, failure: .appUnavailable)), 5)
    }

    func testBitmapPNG() throws {
        let png = TextRenderer.render("Dana", size: .defaultSize, style: TextStyle()).bitmap.pngData()
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}
