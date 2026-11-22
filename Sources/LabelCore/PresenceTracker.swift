import Foundation

/// Remembers when the printer last advertised, so the UI can say whether it's on and nearby.
public struct PresenceTracker {
    public let timeout: TimeInterval
    private var name: String?
    private var lastSeen: Date?

    public init(timeout: TimeInterval = 6) { self.timeout = timeout }

    public mutating func saw(_ name: String, at date: Date) {
        self.name = name
        lastSeen = date
    }

    /// The printer's name if it advertised within `timeout`, otherwise nil.
    public func current(at date: Date) -> String? {
        guard let lastSeen, date.timeIntervalSince(lastSeen) <= timeout else { return nil }
        return name
    }
}
