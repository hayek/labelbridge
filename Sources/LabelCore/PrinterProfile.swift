public enum PrinterProfile: Sendable {
    case d11H, d110

    public init(name: String) {
        self = name == "D110" || name.hasPrefix("D110-") ? .d110 : .d11H
    }

    /// The window and PDF renderer use the D11_H canvas; adapt it after connecting.
    public func prepare(_ bitmap: Bitmap) -> Bitmap {
        guard self == .d110 else { return bitmap }
        let width = max(1, Int((Double(bitmap.width) * 203 / LabelSize.dpi).rounded()))
        let height = 96
        let pixels = (0..<(width * height)).map { i in
            bitmap.isBlack(x: min(bitmap.width - 1, i % width * bitmap.width / width),
                           y: min(bitmap.height - 1, i / width * bitmap.height / height))
        }
        return Bitmap(width: width, height: height, pixels: pixels)
    }
}
