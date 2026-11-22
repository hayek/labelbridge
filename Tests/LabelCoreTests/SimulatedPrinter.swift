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
            if let stop = stopAfterPages, pageEnds >= stop { continue }   // printer went silent
            switch p.cmd {
            case Cmd.connect.rawValue: if answerConnect { reply(0xC2, [3]) }
            case Cmd.setPageSize.rawValue:
                copies = Int(p.data[4]) << 8 | Int(p.data[5])
                reply(0x14, [1, 0])
            case Cmd.pageEnd.rawValue:
                pageEnds += 1
                pageCounter += copies
                reply(0xE4, [1])
            case Cmd.printStatus.rawValue: reply(0xB3, Packet.u16(pageCounter) + [100, 100, 0, 0, 0, 0])
            case Cmd.bitmapRow.rawValue, Cmd.emptyRow.rawValue, Cmd.heartbeat.rawValue: break
            default: if let r = Packet.expectedReply(for: Cmd(rawValue: p.cmd)!) { reply(r, [1]) }
            }
        }
    }

    func close() async { continuation.finish() }

    private func reply(_ cmd: UInt8, _ data: [UInt8]) { continuation.yield(Packet(cmd: cmd, data: data)) }
}
