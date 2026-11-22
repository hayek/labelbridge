/// A 1-bit image in label orientation: `width` = label length in pixels, `height` = print-head pixels.
public struct Bitmap: Equatable, Sendable {
    public let width: Int
    public let height: Int
    private let pixels: [Bool]   // row-major, y = 0 is the top edge

    public init(width: Int, height: Int, pixels: [Bool]) {
        precondition(pixels.count == width * height, "pixel count must equal width × height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func isBlack(x: Int, y: Int) -> Bool { pixels[y * width + x] }
}
