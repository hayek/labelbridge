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

    func testD110UsesLegacyCommandsAndNativePageSizeForTextAndBitmaps() async {
        for textJob in [true, false] {
            let printer = SimulatedPrinter()
            printer.profile = .d110
            let queue = JobQueue(makeLink: { printer }, makeSession: fastSession)
            let settings = PrintSettings(density: 5, copies: 2)
            let result: JobResult
            if textJob {
                var text = job(["One", "Two"])
                text.settings = settings
                result = await queue.submit(text) { _, _ in }
            } else {
                let bitmap = Bitmap(width: 591, height: 142, pixels: [Bool](repeating: true, count: 591 * 142))
                result = await queue.submit(bitmaps: [bitmap, bitmap], settings: settings) { _, _ in }
            }
            XCTAssertTrue(result.ok, result.error ?? "")
            XCTAssertEqual(result.printed, 4)
            let commands = printer.commands.filter { $0 != 0x85 && $0 != 0x84 && $0 != 0xA3 }
            XCTAssertEqual(commands, [0xC1, 0x21, 0x23, 0x01,
                                      0x20, 0x03, 0x13, 0x15, 0xE3,
                                      0x20, 0x03, 0x13, 0x15, 0xE3, 0xF3])
            XCTAssertEqual(printer.sent.first { $0.cmd == 0x01 }?.data, [1])
            XCTAssertEqual(printer.sent.first { $0.cmd == 0x13 }?.data, [1, 144, 0, 96])
            XCTAssertEqual(printer.sent.first { $0.cmd == 0x15 }?.data, [0, 2])
            XCTAssertEqual(printer.sent.first { $0.cmd == 0x21 }?.data, [3])
        }
    }

    func testD110WaitsForPageBeforeClearingNextPage() async {
        let printer = SimulatedPrinter()
        printer.profile = .d110
        printer.labelDuration = .milliseconds(50)
        let counters = CommandLog()
        printer.onSend = { packet in
            if packet.cmd == Cmd.printClear.rawValue { counters.append(UInt8(printer.counter)) }
        }
        let queue = JobQueue(makeLink: { printer }, makeSession: fastSession)
        let result = await queue.submit(job(["One", "Two"])) { _, _ in }
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(counters.all, [0, 1])
    }

    func testTransparent14x28LabelUsesNativeD110DimensionsAndMedia() async {
        let printer = SimulatedPrinter()
        printer.profile = .d110
        let queue = JobQueue(makeLink: { printer }, makeSession: fastSession)
        var transparent = job(["Clear label"])
        transparent.size = LabelSize(14, 28)
        transparent.settings.media = .transparent
        let result = await queue.submit(transparent) { _, _ in }
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(printer.sent.first { $0.cmd == 0x13 }?.data, [0, 224, 0, 96])
        XCTAssertEqual(printer.sent.first { $0.cmd == 0x23 }?.data, [5])
    }
}

final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UInt8] = []
    func append(_ c: UInt8) { lock.lock(); items.append(c); lock.unlock() }
    var all: [UInt8] { lock.lock(); defer { lock.unlock() }; return items }
}

final class D110CopiesTests: XCTestCase {
    /// niimbluelib's D110 task waits after each page until the printer's cumulative page counter
    /// reaches all copies printed so far; with 2 copies of 2 labels, page 2 starts at counter 2.
    func testD110WaitsForEveryCopyBeforeTheNextLabel() async {
        let printer = SimulatedPrinter()
        printer.profile = .d110
        printer.labelDuration = .milliseconds(30)
        let counters = CommandLog()
        printer.onSend = { if $0.cmd == Cmd.printClear.rawValue { counters.append(UInt8(printer.counter)) } }
        let queue = JobQueue(makeLink: { printer }, makeSession: {
            PrintSession(link: $0, replyTimeout: .milliseconds(200), statusTimeout: .seconds(1), rowInterval: .zero, pollInterval: .milliseconds(5))
        })
        let job = LabelJob(items: ["One", "Two", "Three"], size: .defaultSize, style: TextStyle(),
                           settings: PrintSettings(copies: 2), source: .window)
        let result = await queue.submit(job) { _, _ in }
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.printed, 6)
        XCTAssertEqual(counters.all, [0, 2, 4])
    }

    func testStickerJobPrintsOnePagePerCopyOnTheD110() async {
        let printer = SimulatedPrinter()
        printer.profile = .d110
        let queue = JobQueue(makeLink: { printer }, makeSession: {
            PrintSession(link: $0, replyTimeout: .milliseconds(200), statusTimeout: .seconds(1), rowInterval: .zero, pollInterval: .milliseconds(5))
        })
        let job = StickerJob(design: StickerTemplate.builtIn[2].design, settings: PrintSettings(copies: 3, media: .transparent), source: .cli)
        let result = await queue.submit(job) { _, _ in }
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.printed, 3)
        XCTAssertEqual(printer.sent.first { $0.cmd == 0x13 }?.data, [0, 224, 0, 96])
        XCTAssertEqual(printer.sent.first { $0.cmd == 0x15 }?.data, [0, 3])
        XCTAssertEqual(printer.sent.first { $0.cmd == 0x23 }?.data, [5])
    }
}
