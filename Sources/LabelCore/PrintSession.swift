import Foundation

/// Runs the D11_H or legacy D110 print sequence on a connected printer.
/// Reference: MultiMote/niimbluelib (MIT), D110MV4PrintTask and D110PrintTask.
public final class PrintSession: @unchecked Sendable {
    private let link: PrinterLink
    private let replyTimeout: Duration
    private let statusTimeout: Duration
    private let rowInterval: Duration
    private let pollInterval: Duration
    private let inbox = Inbox()
    private var pump: Task<Void, Never>?

    private let pageTimeout: Duration
    private let log: (@Sendable (String) -> Void)?

    public init(link: PrinterLink, replyTimeout: Duration = .seconds(2), pageTimeout: Duration = .seconds(10),
                statusTimeout: Duration = .seconds(20), rowInterval: Duration = .milliseconds(10),
                pollInterval: Duration = .milliseconds(300), log: (@Sendable (String) -> Void)? = nil) {
        self.pageTimeout = pageTimeout
        self.log = log
        self.link = link
        self.replyTimeout = replyTimeout
        self.statusTimeout = statusTimeout
        self.rowInterval = rowInterval
        self.pollInterval = pollInterval
    }

    /// Prints `pages` × `settings.copies` labels and returns how many printed.
    /// D11_H pages are sent back to back, with flow control from setPageSize/pageEnd replies.
    /// The original D110 must finish each page before the next page's clear command.
    /// `progress(printed, total)` is called as the status counter rises.
    public func run(pages: [EncodedPage], settings: PrintSettings, progress: (Int, Int) -> Void) async throws -> Int {
        let replies = link.replies, inbox = self.inbox
        pump = Task { for await p in replies { await inbox.put(p) } }
        defer { pump?.cancel() }

        let total = pages.count * settings.copies
        let legacy = link.profile == .d110
        let density = legacy ? min(settings.density, 3) : settings.density
        if density != settings.density { log?("D110 supports darkness 1–3; using \(density)") }
        do {
            guard try await request(Packet(.connect), expect: 0xC2, tries: 3) != nil else { throw PrintError.busy }
            if legacy {
                try await require(Packet(.setDensity, [UInt8(density)]), 0x31)
                try await require(Packet(.setLabelType, [settings.media.commandValue]), 0x33)
                try await requireOnce(Packet(.printStart), 0x02, what: "D110 print start")
            } else {
                try await require(Packet(.setLabelType, [settings.media.commandValue]), 0x33)
                try await require(Packet(.setDensity, [UInt8(density)]), 0x31)
                // printStart9b: total pages u16, 0,0,0,0, page color (0 = single), speed 1, flag 0
                try await require(Packet(.printStart, Packet.u16(total) + [0, 0, 0, 0, 0, 1, 0]), 0x02)
            }
        } catch let r as PrinterReported {
            await closeJob()
            throw PrintError.printer(code: r.code, printed: 0)
        }

        var printed = 0          // labels the printer's counter has confirmed
        func note(_ status: Packet?) throws {
            guard let status else { return }
            if status.cmd == PrinterReported.packet { throw PrinterReported(code: Int(status.data.first ?? 0)) }
            guard status.data.count >= 2 else { return }
            // The 10-byte status form carries an error byte at offset 6 (niimbluelib parsePrintStatusResponse).
            if status.data.count == 10, status.data[6] != 0 { throw PrinterReported(code: Int(status.data[6])) }
            let counter = min(Int(status.data[0]) << 8 | Int(status.data[1]), total)
            if counter > printed { printed = counter; progress(printed, total) }
        }
        do {
            for (i, page) in pages.enumerated() {
                try note(await inbox.latest(0xB3))                   // answer to the previous one-way status
                if legacy {
                    try await requireOnce(Packet(.printClear), 0x30, what: "D110 clear")
                    try await requireOnce(Packet(.pageStart), 0x04, what: "D110 page start")
                    try await requireOnce(Packet(.setPageSize, Packet.u16(page.rows) + Packet.u16(page.cols)),
                                          0x14, what: "page \(i + 1) size")
                    try await requireOnce(Packet(.printQuantity, Packet.u16(settings.copies)), 0x16, what: "D110 copies")
                } else {
                    try await send(Packet(.printStatus), note: "status (one-way)")
                    // setPageSize13b: rows, cols, copies, cut height, cut type, 0, send-all, part height
                    let size = Packet.u16(page.rows) + Packet.u16(page.cols) + Packet.u16(settings.copies) + Packet.u16(0) + [0, 0, 0] + Packet.u16(0)
                    try await requireOnce(Packet(.setPageSize, size), 0x14, what: "page \(i + 1) size")
                }
                for row in page.packets {
                    try await link.send(row.bytes())
                    if rowInterval > .zero { try await Task.sleep(for: rowInterval) }
                }
                try await requireOnce(Packet(.pageEnd), 0xE4, what: "page \(i + 1) end")
                if legacy { try await waitUntilPrinted((i + 1) * settings.copies, note: note) }
            }
            try await waitUntilPrinted(total, note: note)
        } catch let r as PrinterReported {
            await closeJob()
            throw PrintError.printer(code: r.code, printed: printed)
        } catch {
            await closeJob()
            throw PrintError.failedMidJob(printed: printed)
        }
        _ = try? await request(Packet(.printEnd), expect: 0xF4, tries: 3)
        if !legacy { try? await link.send(Packet(.heartbeat, [1]).bytes()) }
        return printed
    }

    /// Polls the status until `total` labels are out. Fails only after `statusTimeout` with no change
    /// at all (counter or progress bytes), so long jobs with many copies never time out while printing.
    private func waitUntilPrinted(_ total: Int, note: (Packet?) throws -> Void) async throws {
        var lastChange = ContinuousClock.now
        var lastData: [UInt8] = []
        while true {
            let status = try await request(Packet(.printStatus), expect: 0xB3, tries: 1, quiet: true)
            try note(status)
            if let status {
                if status.data.count >= 2, Int(status.data[0]) << 8 | Int(status.data[1]) >= total { return }
                if status.data != lastData { lastData = status.data; lastChange = .now }
            }
            if ContinuousClock.now - lastChange > statusTimeout {
                log?("no progress for \(statusTimeout); giving up")
                throw PrintError.timeout
            }
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Ends a failed job on the printer so it isn't left waiting for pages (best effort, no reply needed).
    private func closeJob() async {
        log?("closing the failed job")
        try? await link.send(Packet(.printEnd).bytes())
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func require(_ packet: Packet, _ reply: UInt8, tries: Int = 3) async throws {
        guard try await request(packet, expect: reply, tries: tries) != nil else { throw PrintError.timeout }
    }

    /// Sends once and waits up to `pageTimeout`: the printer answers page commands when it has room,
    /// and resending would give it a duplicate page command (niimbluelib uses one try, 10 s).
    private func requireOnce(_ packet: Packet, _ reply: UInt8, what: String) async throws {
        await inbox.discard(reply)
        try await send(packet, note: what)
        guard let p = await inbox.take(reply, timeout: pageTimeout) else {
            log?("no answer to \(what) within \(pageTimeout)")
            throw PrintError.timeout
        }
        if p.cmd == PrinterReported.packet { throw PrinterReported(code: Int(p.data.first ?? 0)) }
    }

    private func request(_ packet: Packet, expect reply: UInt8, tries: Int, quiet: Bool = false) async throws -> Packet? {
        await inbox.discard(reply)
        for attempt in 1...tries {
            try await send(packet, note: quiet ? nil : (attempt > 1 ? "try \(attempt)" : ""))
            if let p = await inbox.take(reply, timeout: replyTimeout) {
                if p.cmd == PrinterReported.packet { throw PrinterReported(code: Int(p.data.first ?? 0)) }
                return p
            }
        }
        if !quiet { log?(String(format: "no answer to %02X after %d tries", packet.cmd, tries)) }
        return nil
    }

    /// Sends a command, logging it unless `note` is nil (rows and status polls aren't logged).
    private func send(_ packet: Packet, note: String?) async throws {
        if let note {
            let data = packet.data.map { String(format: "%02x", $0) }.joined(separator: " ")
            log?(String(format: "→ printer %02X ", packet.cmd) + data + (note.isEmpty ? "" : "  (\(note))"))
        }
        try await link.send(packet.bytes())
    }
}

/// The printer stopped with its error packet (0xDB).
struct PrinterReported: Error {
    static let packet: UInt8 = 0xDB
    let code: Int
}

/// Holds packets from the printer until someone asks for one with a given command.
/// A printer error packet answers every wait from then on, so no step waits out its timeout.
actor Inbox {
    private var packets: [Packet] = []
    private var waiter: (cmd: UInt8, token: Int, cont: CheckedContinuation<Packet?, Never>)?
    private var nextToken = 0

    private var printerError: Packet?

    func put(_ p: Packet) {
        if p.cmd == PrinterReported.packet {
            printerError = p
            if let w = waiter { waiter = nil; w.cont.resume(returning: p) }
            return
        }
        if let w = waiter, w.cmd == p.cmd { waiter = nil; w.cont.resume(returning: p) } else { packets.append(p) }
    }

    func discard(_ cmd: UInt8) { packets.removeAll { $0.cmd == cmd } }

    /// Removes every queued packet with `cmd` and returns the newest one (no waiting).
    func latest(_ cmd: UInt8) -> Packet? {
        if let e = printerError { return e }
        let last = packets.last { $0.cmd == cmd }
        discard(cmd)
        return last
    }

    func take(_ cmd: UInt8, timeout: Duration) async -> Packet? {
        if let e = printerError { return e }
        if let i = packets.firstIndex(where: { $0.cmd == cmd }) { return packets.remove(at: i) }
        nextToken += 1
        let token = nextToken
        return await withCheckedContinuation { cont in
            waiter = (cmd, token, cont)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expire(token)
            }
        }
    }

    /// Times out only the wait that started this timer, never a later one.
    private func expire(_ token: Int) {
        if let w = waiter, w.token == token { waiter = nil; w.cont.resume(returning: nil) }
    }
}
