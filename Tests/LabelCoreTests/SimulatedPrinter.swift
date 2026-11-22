@testable import LabelCore

/// A fake D11 that answers like the real printer: each command's reply, and a page counter
/// (advanced by `copies` on every pageEnd) reported by printStatus.
final class SimulatedPrinter: PrinterLink, @unchecked Sendable {
    private(set) var sent: [Packet] = []
    private var parser = FrameParser()
    private var continuation: AsyncStream<Packet>.Continuation!
    let replies: AsyncStream<Packet>
    private var pageCounter = 0
    private var copies = 1
    private var pageEnds = 0
    var answerConnect = true
    var stopAfterPages: Int?
    /// After this many pages, the printer reports `errorCode` in a 0xDB packet and goes silent (red LED).
    var errorAfterPages: Int?
    var errorCode: UInt8 = 0x08
    /// When set, status replies are the 10-byte form carrying this error byte.
    var statusErrorCode: UInt8?
    private var errored = false
    /// When set, each label takes this long to print after its pageEnd (the counter rises over time).
    var labelDuration: Duration?
    /// Delay before answering setPageSize (a busy printer answers late).
    var pageSizeReplyDelay: Duration?
    /// When true, healthy status replies use the 10-byte form with a zero error byte.
    var tenByteStatus = false
    private var queuedLabels = 0
    private var printing: Task<Void, Never>?
    /// Labels printed so far, as the printer's counter reports it.
    var counter: Int { pageCounter }
    var onSend: ((Packet) -> Void)?

    init() {
        var c: AsyncStream<Packet>.Continuation!
        replies = AsyncStream { c = $0 }
        continuation = c
    }

    var commands: [UInt8] { sent.map(\.cmd) }

    func send(_ bytes: [UInt8]) async throws {
        let frame = bytes.first == 0x03 ? Array(bytes.dropFirst()) : bytes
        for p in parser.feed(frame) {
            sent.append(p)
            onSend?(p)
            if let stop = stopAfterPages, pageEnds >= stop { continue }   // printer went silent
            if errored { continue }
            if let n = errorAfterPages, pageEnds >= n, p.cmd == Cmd.printStatus.rawValue {
                errored = true
                reply(0xDB, [errorCode])
                continue
            }
            if let code = statusErrorCode, p.cmd == Cmd.printStatus.rawValue {
                reply(0xB3, Packet.u16(pageCounter) + [0, 0, 0, 0, code, 0, 0, 0])
                continue
            }
            switch p.cmd {
            case Cmd.connect.rawValue: if answerConnect { reply(0xC2, [3]) }
            case Cmd.setPageSize.rawValue:
                copies = Int(p.data[4]) << 8 | Int(p.data[5])
                if let d = pageSizeReplyDelay {
                    Task { try? await Task.sleep(for: d); self.reply(0x14, [1, 0]) }
                } else {
                    reply(0x14, [1, 0])
                }
            case Cmd.pageEnd.rawValue:
                pageEnds += 1
                if let d = labelDuration {
                    queuedLabels += copies
                    if printing == nil {
                        printing = Task {
                            while self.queuedLabels > 0 {
                                try? await Task.sleep(for: d)
                                self.queuedLabels -= 1
                                self.pageCounter += 1
                            }
                            self.printing = nil
                        }
                    }
                } else {
                    pageCounter += copies
                }
                reply(0xE4, [1])
            case Cmd.printStatus.rawValue:
                reply(0xB3, Packet.u16(pageCounter) + (tenByteStatus ? [100, 100, 0, 0, 0, 0, 0, 0] : [100, 100, 0, 0, 0, 0]))
            case Cmd.bitmapRow.rawValue, Cmd.emptyRow.rawValue, Cmd.heartbeat.rawValue: break
            default: if let r = Packet.expectedReply(for: Cmd(rawValue: p.cmd)!) { reply(r, [1]) }
            }
        }
    }

    func close() async { continuation.finish() }

    private func reply(_ cmd: UInt8, _ data: [UInt8]) { continuation.yield(Packet(cmd: cmd, data: data)) }
}
