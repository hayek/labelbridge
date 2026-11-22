/// A byte pipe to a printer (Bluetooth in the app, simulated in tests).
public protocol PrinterLink: AnyObject, Sendable {
    func send(_ bytes: [UInt8]) async throws
    /// Parsed packets from the printer.
    var replies: AsyncStream<Packet> { get }
    func close() async
}

public struct PrintSettings: Codable, Hashable, Sendable {
    public var density: Int     // 1–5
    public var copies: Int      // ≥ 1
    public init(density: Int = 3, copies: Int = 1) {
        self.density = min(max(density, 1), 5)
        self.copies = max(copies, 1)
    }
}

public enum PrintError: Error, Equatable, Sendable {
    case notFound
    case busy
    case failedMidJob(printed: Int)
    case timeout
}
