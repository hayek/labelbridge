import Foundation

/// Physical label size. `widthMM` is the short side (across the print head), `lengthMM` the long side.
public struct LabelSize: Codable, Hashable, Sendable, CustomStringConvertible {
    public static let dpi = 300.0
    public static let headPixels = 142            // D11_H print head (12 mm)
    public static let endMarginPixels = 24        // 2 mm at 300 dpi

    public var widthMM: Double
    public var lengthMM: Double

    public init(_ widthMM: Double, _ lengthMM: Double) {
        self.widthMM = min(widthMM, lengthMM)
        self.lengthMM = max(widthMM, lengthMM)
    }

    public static let defaultSize = LabelSize(15, 50)
    public static let builtIn: [LabelSize] = [
        LabelSize(15, 50), LabelSize(12, 40), LabelSize(14, 40), LabelSize(15, 30),
        LabelSize(12, 22), LabelSize(14, 22), LabelSize(15, 40),
        LabelSize(14, 28),
    ]

    /// Parses "50x15", "15x50", "15×50" or "15 x 50 mm".
    public init?(parsing text: String) {
        let parts = text.lowercased().replacingOccurrences(of: "mm", with: "")
            .split(whereSeparator: { $0 == "x" || $0 == "×" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), a > 0, b > 0 else { return nil }
        self.init(a, b)
    }

    /// Canvas in label orientation: length along the label, height = print head (the printable band).
    public var canvasPixels: (length: Int, height: Int) {
        (Int((lengthMM / 25.4 * Self.dpi).rounded()), Self.headPixels)
    }

    public var description: String {
        func f(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(v) }
        return "\(f(widthMM))x\(f(lengthMM))"
    }
}
