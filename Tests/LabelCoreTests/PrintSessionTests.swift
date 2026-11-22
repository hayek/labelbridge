import XCTest
@testable import LabelCore

final class PrintSessionTests: XCTestCase {
    private func page(_ rows: Int = 4) -> EncodedPage {
        RowEncoder.encode(Bitmap(width: rows, height: 142, pixels: (0..<(rows * 142)).map { $0 % 3 == 0 }))
    }

    private func session(_ link: SimulatedPrinter) -> PrintSession {
        PrintSession(link: link, replyTimeout: .milliseconds(100), pageTimeout: .milliseconds(300),
                     statusTimeout: .milliseconds(600), rowInterval: .zero, pollInterval: .milliseconds(10))
    }

    private func setup(_ c: [UInt8]) -> [UInt8] { c.filter { $0 != Cmd.bitmapRow.rawValue && $0 != Cmd.emptyRow.rawValue } }

    func testSingleLabelSequence() async throws {
        let printer = SimulatedPrinter()
        let printed = try await session(printer).run(pages: [page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
        XCTAssertEqual(printed, 1)
        let c = setup(printer.commands)
        XCTAssertEqual(Array(c.prefix(7)), [0xC1, 0x23, 0x21, 0x01, 0xA3, 0x13, 0xE3])
        XCTAssertEqual(Array(c.suffix(2)), [0xF3, 0xDC])
        XCTAssertEqual(printer.sent.first { $0.cmd == 0x21 }?.data, [3])
    }

    func testThreeLabelsOneSession() async throws {
        let printer = SimulatedPrinter()
        var last = (0, 0)
        let printed = try await session(printer).run(pages: [page(), page(), page()], settings: PrintSettings(density: 3, copies: 1)) { last = ($0, $1) }
        XCTAssertEqual(printed, 3)
        XCTAssertEqual(last.0, 3); XCTAssertEqual(last.1, 3)
        XCTAssertEqual(printer.commands.filter { $0 == 0xC1 }.count, 1)
        XCTAssertEqual(printer.commands.filter { $0 == 0x13 }.count, 3)
        XCTAssertEqual(printer.commands.filter { $0 == 0xE3 }.count, 3)
        XCTAssertEqual(Array(printer.sent.first { $0.cmd == 0x01 }!.data.prefix(2)), [0, 3])
    }

    func testCopiesMultiplyTotal() async throws {
        let printer = SimulatedPrinter()
        let printed = try await session(printer).run(pages: [page(), page()], settings: PrintSettings(density: 3, copies: 2)) { _, _ in }
        XCTAssertEqual(printed, 4)
        XCTAssertEqual(Array(printer.sent.first { $0.cmd == 0x01 }!.data.prefix(2)), [0, 4])
        XCTAssertEqual(Array(printer.sent.first { $0.cmd == 0x13 }!.data[4..<6]), [0, 2])
    }

    func testLinkDropMidBatchReportsPrintedCount() async {
        let printer = SimulatedPrinter()
        printer.stopAfterPages = 2
        let start = Date()
        do {
            _ = try await session(printer).run(pages: [page(), page(), page(), page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? PrintError, .failedMidJob(printed: 1))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testNoConnectReplyIsBusy() async {
        let printer = SimulatedPrinter()
        printer.answerConnect = false
        do {
            _ = try await session(printer).run(pages: [page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
            XCTFail("expected busy")
        } catch {
            XCTAssertEqual(error as? PrintError, .busy)
        }
    }
}

final class InboxTests: XCTestCase {
    func testEarlierTimeoutDoesNotCancelLaterWait() async {
        let inbox = Inbox()
        Task { try? await Task.sleep(for: .milliseconds(10)); await inbox.put(Packet(cmd: 0xB3)) }
        let first = await inbox.take(0xB3, timeout: .milliseconds(200))   // satisfied quickly; its timer keeps running
        XCTAssertNotNil(first)
        Task { try? await Task.sleep(for: .milliseconds(350)); await inbox.put(Packet(cmd: 0xB3)) }
        let second = await inbox.take(0xB3, timeout: .seconds(2))         // must survive the first wait's timer at ~200 ms
        XCTAssertNotNil(second)
    }
}

final class PrinterErrorTests: XCTestCase {
    private func page() -> EncodedPage {
        RowEncoder.encode(Bitmap(width: 4, height: 142, pixels: (0..<(4 * 142)).map { $0 % 3 == 0 }))
    }
    /// A long status timeout: a printer error must end the job right away, not after this.
    private func session(_ link: SimulatedPrinter) -> PrintSession {
        PrintSession(link: link, replyTimeout: .milliseconds(100), statusTimeout: .seconds(20),
                     rowInterval: .zero, pollInterval: .milliseconds(10))
    }

    func testPrinterErrorPacketEndsTheJobAtOnceWithItsCode() async {
        let printer = SimulatedPrinter()
        printer.errorAfterPages = 2       // label 1 done, error while label 2 prints
        printer.errorCode = 0x08
        let start = Date()
        do {
            _ = try await session(printer).run(pages: [page(), page(), page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? PrintError, .printer(code: 8, printed: 1))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
    }

    func testErrorByteInStatusReplyEndsTheJob() async {
        let printer = SimulatedPrinter()
        printer.statusErrorCode = 0x02
        do {
            _ = try await session(printer).run(pages: [page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? PrintError, .printer(code: 2, printed: 0))
        }
    }

    func testPrinterErrorBecomesAReadableResult() {
        let r = JobQueue.failureResult(PrintError.printer(code: 2, printed: 3), total: 9)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.printed, 3)
        XCTAssertEqual(r.failure, .printerError)
        XCTAssertTrue(r.error?.contains("out of labels") == true, r.error ?? "")
        XCTAssertTrue(r.error?.contains("3 of 9") == true, r.error ?? "")
        XCTAssertEqual(ExitCode.for(r), 4)
    }

    func testUnknownPrinterErrorCodeStillNamesTheCode() {
        XCTAssertTrue(PrinterProblem.describe(0x99).contains("153"))
        XCTAssertTrue(PrinterProblem.describe(0x01).lowercased().contains("lid"))
    }
}

/// The flow follows niimbluelib's D110M v4 task: all pages back to back, then one status wait.
final class PrintFlowTests: XCTestCase {
    private func page() -> EncodedPage {
        RowEncoder.encode(Bitmap(width: 4, height: 142, pixels: (0..<(4 * 142)).map { $0 % 3 == 0 }))
    }
    private func session(_ link: SimulatedPrinter, status: Duration = .milliseconds(600)) -> PrintSession {
        PrintSession(link: link, replyTimeout: .milliseconds(100), pageTimeout: .seconds(1), statusTimeout: status,
                     rowInterval: .zero, pollInterval: .milliseconds(10))
    }

    func testPagesAreSentBackToBackWithoutWaitingForEachLabel() async throws {
        let printer = SimulatedPrinter()
        printer.labelDuration = .milliseconds(150)
        var counterAtLastPageEnd = -1
        var pageEnds = 0
        printer.onSend = { p in
            if p.cmd == Cmd.pageEnd.rawValue { pageEnds += 1; if pageEnds == 3 { counterAtLastPageEnd = printer.counter } }
        }
        let printed = try await session(printer).run(pages: [page(), page(), page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
        XCTAssertEqual(printed, 3)
        XCTAssertLessThan(counterAtLastPageEnd, 2, "page 3 should be sent before label 2 finishes printing")
    }

    func testManyCopiesOnASlowPrinterDoNotTimeOut() async throws {
        let printer = SimulatedPrinter()
        printer.labelDuration = .milliseconds(150)     // 6 labels ≈ 0.9 s, longer than the 0.4 s status timeout
        var progress: [Int] = []
        let printed = try await session(printer, status: .milliseconds(400))
            .run(pages: [page()], settings: PrintSettings(density: 3, copies: 6)) { done, _ in progress.append(done) }
        XCTAssertEqual(printed, 6)
        XCTAssertEqual(progress.last, 6)
        XCTAssertGreaterThan(progress.count, 1, "progress is reported as labels finish")
    }

    func testSlowPageSizeAnswerIsNotResent() async throws {
        let printer = SimulatedPrinter()
        printer.pageSizeReplyDelay = .milliseconds(300)   // later than the 100 ms reply timeout, within the page timeout
        _ = try await session(printer).run(pages: [page(), page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
        XCTAssertEqual(printer.commands.filter { $0 == Cmd.setPageSize.rawValue }.count, 2)
    }

    func testAFailedJobIsClosedOnThePrinter() async {
        let printer = SimulatedPrinter()
        printer.errorAfterPages = 1
        _ = try? await session(printer).run(pages: [page(), page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
        XCTAssertEqual(printer.commands.last, Cmd.printEnd.rawValue)
    }

    func testHealthyTenByteStatusIsNotAnError() async throws {
        let printer = SimulatedPrinter()
        printer.tenByteStatus = true
        let printed = try await session(printer).run(pages: [page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
        XCTAssertEqual(printed, 1)
    }

    func testSentCommandsAreLogged() async throws {
        let printer = SimulatedPrinter()
        let lines = LogLines()
        let s = PrintSession(link: printer, replyTimeout: .milliseconds(100), pageTimeout: .seconds(1), statusTimeout: .milliseconds(600),
                             rowInterval: .zero, pollInterval: .milliseconds(10), log: { lines.add($0) })
        _ = try await s.run(pages: [page()], settings: PrintSettings(density: 3, copies: 1)) { _, _ in }
        XCTAssertTrue(lines.all.contains { $0.contains("→ printer 13") }, lines.all.joined(separator: "\n"))
        XCTAssertTrue(lines.all.contains { $0.contains("→ printer E3") })
        XCTAssertFalse(lines.all.contains { $0.contains("→ printer 85") }, "rows are not logged")
    }
}

final class LogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
