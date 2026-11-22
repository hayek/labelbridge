/// One page ready to send: its size and the row packets.
public struct EncodedPage: Equatable, Sendable {
    public let rows: Int
    public let cols: Int
    public let packets: [Packet]
}

/// Rotates a label bitmap 90° clockwise into printer rows ("left" print direction)
/// and compresses identical consecutive rows.
public enum RowEncoder {
    public static func encode(_ bitmap: Bitmap) -> EncodedPage {
        let rows = bitmap.width
        let cols = (bitmap.height + 7) / 8 * 8
        var packets: [Packet] = []
        var current: (pos: Int, repeats: Int, bytes: [UInt8])?

        func flush() {
            guard let run = current else { return }
            if run.bytes.allSatisfy({ $0 == 0 }) {
                packets.append(Packet(.emptyRow, Packet.u16(run.pos) + [UInt8(run.repeats)]))
            } else {
                let count = run.bytes.reduce(0) { $0 + $1.nonzeroBitCount }
                // pixel count in "total" mode: [0, lo, hi]
                let header = Packet.u16(run.pos) + [0, UInt8(count & 0xFF), UInt8((count >> 8) & 0xFF), UInt8(run.repeats)]
                packets.append(Packet(.bitmapRow, header + run.bytes))
            }
            current = nil
        }

        for r in 0..<rows {
            var bytes = [UInt8](repeating: 0, count: cols / 8)
            for c in 0..<bitmap.height where bitmap.isBlack(x: r, y: bitmap.height - 1 - c) {
                bytes[c / 8] |= UInt8(0x80 >> (c % 8))
            }
            if let run = current, run.bytes == bytes, run.repeats < 255 {
                current!.repeats += 1
            } else {
                flush()
                current = (r, 1, bytes)
            }
        }
        flush()
        return EncodedPage(rows: rows, cols: cols, packets: packets)
    }
}
