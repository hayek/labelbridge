/// Reassembles packets from a byte stream that may split or join frames.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Packet] {
        buffer += bytes
        var packets: [Packet] = []
        while true {
            guard let start = headerIndex() else {
                // keep a trailing 0x55 that may start the next frame
                buffer = buffer.last == 0x55 ? [0x55] : []
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 4 else { break }
            let length = Int(buffer[3])
            let total = 4 + length + 3
            guard buffer.count >= total else { break }
            let frame = Array(buffer[0..<total])
            let packet = Packet(cmd: frame[2], data: Array(frame[4..<(4 + length)]))
            if frame[total - 3] == packet.checksum, frame[total - 2] == 0xAA, frame[total - 1] == 0xAA {
                packets.append(packet)
                buffer.removeFirst(total)
            } else {
                buffer.removeFirst(2)   // not a valid frame here; resync after this header
            }
        }
        return packets
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0..<(buffer.count - 1) where buffer[i] == 0x55 && buffer[i + 1] == 0x55 { return i }
        return nil
    }
}
