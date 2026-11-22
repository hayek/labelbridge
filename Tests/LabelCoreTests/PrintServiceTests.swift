import XCTest
@testable import LabelCore

final class PrintServiceTests: XCTestCase {
    private func fastSession(_ link: PrinterLink) -> PrintSession {
        PrintSession(link: link, replyTimeout: .milliseconds(200), statusTimeout: .seconds(1),
                     rowInterval: .zero, pollInterval: .milliseconds(5))
    }

    private func job(_ items: [String]) -> LabelJob {
        LabelJob(items: items, size: .defaultSize, style: TextStyle(), settings: PrintSettings(), source: .window)
    }

    func testJobsAreSerialized() async {
        let log = CommandLog()
        let queue = JobQueue(makeLink: {
            let p = SimulatedPrinter()
            p.onSend = { log.append($0.cmd) }
            return p
        }, makeSession: fastSession)
        async let a = queue.submit(job(["A1", "A2"])) { _, _ in }
        async let b = queue.submit(job(["B1"])) { _, _ in }
        let (ra, rb) = await (a, b)
        XCTAssertTrue(ra.ok); XCTAssertTrue(rb.ok)
        let cmds = log.all
        let connects = cmds.indices.filter { cmds[$0] == Cmd.connect.rawValue }
        let firstEnd = cmds.firstIndex(of: Cmd.printEnd.rawValue)!
        XCTAssertEqual(connects.count, 2)
        XCTAssertLessThan(firstEnd, connects[1], "second job started before the first finished")
    }

    func testResultCountsSkippedAndWarnings() async {
        let queue = JobQueue(makeLink: { SimulatedPrinter() }, makeSession: fastSession)
        let r = await queue.submit(job(["A", "  ", String(repeating: "Very long label ", count: 20)])) { _, _ in }
        XCTAssertTrue(r.ok)
        XCTAssertEqual(r.printed, 2)
        XCTAssertEqual(r.total, 2)
        XCTAssertEqual(r.skipped, 1)
        XCTAssertEqual(r.warnings.count, 1)
    }

    func testNoItemsIsBadInput() async {
        let queue = JobQueue(makeLink: { SimulatedPrinter() }, makeSession: fastSession)
        let r = await queue.submit(job(["", " "])) { _, _ in }
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.failure, .badInput)
    }

    func testPrinterNotFoundIsReported() async {
        let queue = JobQueue(makeLink: { throw PrintError.notFound }, makeSession: fastSession)
        let r = await queue.submit(job(["A"])) { _, _ in }
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.failure, .notFound)
        XCTAssertEqual(r.printed, 0)
    }
}

final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UInt8] = []
    func append(_ c: UInt8) { lock.lock(); items.append(c); lock.unlock() }
    var all: [UInt8] { lock.lock(); defer { lock.unlock() }; return items }
}
