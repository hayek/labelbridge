import Foundation

/// Runs one print job on a connected printer: the NIIMBOT "D110M v4" sequence used by the D11_H.
/// Reference: MultiMote/niimbluelib (MIT), D110MV4PrintTask.
public final class PrintSession: @unchecked Sendable {
    private let link: PrinterLink
    private let replyTimeout: Duration
    private let statusTimeout: Duration
    private let rowInterval: Duration
    private let pollInterval: Duration
    private let inbox = Inbox()
    private var pump: Task<Void, Never>?

    public init(link: PrinterLink, replyTimeout: Duration = .seconds(2), statusTimeout: Duration = .seconds(20),
                rowInterval: Duration = .milliseconds(10), pollInterval: Duration = .milliseconds(300)) {
        self.link = link
        self.replyTimeout = replyTimeout
        self.statusTimeout = statusTimeout
        self.rowInterval = rowInterval
        self.pollInterval = pollInterval
    }

    /// Prints `pages` × `settings.copies` labels and returns how many printed.
    /// `progress(printed, total)` is called after each label finishes.
    public func run(pages: [EncodedPage], settings: PrintSettings, progress: (Int, Int) -> Void) async throws -> Int {
        let replies = link.replies, inbox = self.inbox
        pump = Task { for await p in replies { await inbox.put(p) } }
        defer { pump?.cancel() }

        let total = pages.count * settings.copies
        guard try await request(Packet(.connect), expect: 0xC2, tries: 3) != nil else { throw PrintError.busy }
        try await require(Packet(.setLabelType, [1]), 0x33)
        try await require(Packet(.setDensity, [UInt8(settings.density)]), 0x31)
        // printStart9b: total pages u16, 0,0,0,0, page color (0 = single), speed 1, flag 0
        try await require(Packet(.printStart, Packet.u16(total) + [0, 0, 0, 0, 0, 1, 0]), 0x02)

        var printed = 0
        do {
            for page in pages {
                try await link.send(Packet(.printStatus).bytes())       // sent without waiting, like the official app
                // setPageSize13b: rows, cols, copies, cut height, cut type, 0, send-all, part height
                let size = Packet.u16(page.rows) + Packet.u16(page.cols) + Packet.u16(settings.copies) + Packet.u16(0) + [0, 0, 0] + Packet.u16(0)
                try await require(Packet(.setPageSize, size), 0x14)
                for row in page.packets {
                    try await link.send(row.bytes())
                    if rowInterval > .zero { try await Task.sleep(for: rowInterval) }
                }
                try await require(Packet(.pageEnd), 0xE4, tries: 5)
                try await waitForPageCounter(printed + settings.copies)
                printed += settings.copies
                progress(printed, total)
            }
        } catch {
            throw PrintError.failedMidJob(printed: printed)
        }
        _ = try? await request(Packet(.printEnd), expect: 0xF4, tries: 3)
        try? await link.send(Packet(.heartbeat, [1]).bytes())
        return printed
    }

    private func waitForPageCounter(_ target: Int) async throws {
        let deadline = ContinuousClock.now + statusTimeout
        await inbox.discard(0xB3)    // drop the reply to the un-awaited printStatus
        while ContinuousClock.now < deadline {
            if let s = try await request(Packet(.printStatus), expect: 0xB3, tries: 1), s.data.count >= 2,
               Int(s.data[0]) << 8 | Int(s.data[1]) >= target { return }
            try await Task.sleep(for: pollInterval)
        }
        throw PrintError.timeout
    }

    private func require(_ packet: Packet, _ reply: UInt8, tries: Int = 3) async throws {
        guard try await request(packet, expect: reply, tries: tries) != nil else { throw PrintError.timeout }
    }

    private func request(_ packet: Packet, expect reply: UInt8, tries: Int) async throws -> Packet? {
        for _ in 0..<tries {
            try await link.send(packet.bytes())
            if let p = await inbox.take(reply, timeout: replyTimeout) { return p }
        }
        return nil
    }
}

/// Holds packets from the printer until someone asks for one with a given command.
actor Inbox {
    private var packets: [Packet] = []
    private var waiter: (cmd: UInt8, token: Int, cont: CheckedContinuation<Packet?, Never>)?
    private var nextToken = 0

    func put(_ p: Packet) {
        if let w = waiter, w.cmd == p.cmd { waiter = nil; w.cont.resume(returning: p) } else { packets.append(p) }
    }

    func discard(_ cmd: UInt8) { packets.removeAll { $0.cmd == cmd } }

    func take(_ cmd: UInt8, timeout: Duration) async -> Packet? {
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
