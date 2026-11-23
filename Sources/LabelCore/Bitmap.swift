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

    /// Number of black pixels.
    public var inkCount: Int { pixels.reduce(0) { $0 + ($1 ? 1 : 0) } }

    /// The same image moved by whole pixels (+dx right, +dy down); ink moved off the edge is dropped.
    public func shifted(dx: Int, dy: Int) -> Bitmap {
        guard dx != 0 || dy != 0 else { return self }
        var out = [Bool](repeating: false, count: pixels.count)
        for y in 0..<height where (0..<height).contains(y - dy) {
            for x in 0..<width where (0..<width).contains(x - dx) {
                out[y * width + x] = pixels[(y - dy) * width + x - dx]
            }
        }
        return Bitmap(width: width, height: height, pixels: out)
    }
}

import AppKit

extension Bitmap {
    /// PNG of the label as it will print (black on white).
    public func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: width, bitsPerPixel: 8)!
        let p = rep.bitmapData!
        for y in 0..<height { for x in 0..<width { p[y * width + x] = isBlack(x: x, y: y) ? 0 : 255 } }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
