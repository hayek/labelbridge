import XCTest
@testable import LabelCore

/// Regression tests for the final whole-branch review findings.
final class ReviewFixTests: XCTestCase {
    private let job = LabelJob(items: ["Dana"], size: .defaultSize, style: TextStyle(),
                               settings: PrintSettings(density: 3, copies: 1), source: .cli)
    private func socketPath() -> String { NSTemporaryDirectory() + "lb-\(UUID().uuidString.prefix(8)).sock" }

    // C1: a client that disconnects mid-job must not kill the server process with SIGPIPE.
    func testServerSurvivesClientDisconnectMidJob() throws {
        let path = socketPath()
        let finished = expectation(description: "handler finished writing")
        let server = try IPCServer(path: path) { _, send in
            for i in 1...20 { send(.progress(i, 20)); try? await Task.sleep(for: .milliseconds(20)) }
            send(.result(JobResult(ok: true, printed: 20, total: 20)))
            finished.fulfill()
        }
        defer { server.stop() }
        // Raw client: send the request, then hang up without reading.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in for (i, b) in Array(path.utf8).enumerated() { buf[i] = b } }
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        XCTAssertEqual(ok, 0)
        let req = try IPCCoding.encode(IPCRequest.print(job))
        _ = req.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
        close(fd)
        wait(for: [finished], timeout: 5)   // reaching here means the process survived
    }

    // I1: only a failed connect means "app not running"; a drop after sending is a different error.
    func testConnectFailureIsNotRunning() {
        XCTAssertThrowsError(try IPCClient(path: socketPath()).send(.status) { _, _ in }) { error in
            XCTAssertEqual(error as? IPCError, .notRunning)
        }
    }

    func testDropAfterRequestIsClosedNotNotRunning() throws {
        let path = socketPath()
        let server = try IPCServer(path: path) { _, _ in }   // reads the request, replies nothing, hangs up
        defer { server.stop() }
        XCTAssertThrowsError(try IPCClient(path: path).send(.print(job)) { _, _ in }) { error in
            XCTAssertEqual(error as? IPCError, .closed)
        }
    }

    // I4: Windows line endings and a final newline aren't blank labels.
    func testCRLFListHasNoSkippedLines() {
        let r = Batch.items(from: "Dana\r\nYossi\r\n")
        XCTAssertEqual(r.items, ["Dana", "Yossi"])
        XCTAssertEqual(r.skipped, 0)
    }

    func testLinesDropTrailingNewlineAndSplitCRLF() {
        XCTAssertEqual(Batch.lines(from: "a\r\nb\n\n"), ["a", "b"])
        XCTAssertEqual(Batch.lines(from: "a\n\nb"), ["a", "", "b"])
    }
}
