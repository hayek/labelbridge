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
    /// The printer reported an error (its LED turns red); `printed` labels finished before it.
    case printer(code: Int, printed: Int)
}

/// Readable text for the printer's own error codes (from niimbluelib's PrinterErrorCode).
public enum PrinterProblem {
    public static func describe(_ code: Int) -> String {
        switch code {
        case 0x01: return "The lid is open. Close it firmly."
        case 0x02: return "The printer is out of labels or can't detect them. Check that the roll is seated and the lid is closed."
        case 0x03: return "The battery is low. Charge the printer."
        case 0x04: return "The printer reports a battery problem."
        case 0x05: return "Printing was cancelled on the printer."
        case 0x06: return "The printer rejected the print data."
        case 0x07: return "The printer is overheated. Let it cool down."
        case 0x08: return "A label didn't feed out properly. Open the lid, reseat the label roll and close it."
        case 0x09: return "The printer is busy."
        case 0x0B: return "The printer is too cold."
        case 0x10: return "The printer doesn't accept these labels."
        case 0x1C: return "The printer couldn't find the next label. Reseat the label roll."
        case 0x34: return "The printer timed out waiting for data."
        default: return "The printer reported error code \(code)."
        }
    }
}
