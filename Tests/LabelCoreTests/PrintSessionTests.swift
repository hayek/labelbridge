import XCTest
@testable import LabelCore

final class PrintSessionTests: XCTestCase {
    private func page(_ rows: Int = 4) -> EncodedPage {
        RowEncoder.encode(Bitmap(width: rows, height: 142, pixels: (0..<(rows * 142)).map { $0 % 3 == 0 }))
    }

    private func session(_ link: SimulatedPrinter) -> PrintSession {
        PrintSession(link: link, replyTimeout: .milliseconds(100), statusTimeout: .milliseconds(600),
                     rowInterval: .zero, pollInterval: .milliseconds(10))
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
