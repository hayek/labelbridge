/// NIIMBOT printer commands used by LabelBridge.
/// Reference: MultiMote/niimbluelib (MIT), `RequestCommandId`.
public enum Cmd: UInt8, Sendable {
    case connect = 0xC1
    case setLabelType = 0x23
    case setDensity = 0x21
    case printStart = 0x01
    case printClear = 0x20
    case pageStart = 0x03
    case printQuantity = 0x15
    case printStatus = 0xA3
    case setPageSize = 0x13
    case bitmapRow = 0x85
    case emptyRow = 0x84
    case pageEnd = 0xE3
    case printEnd = 0xF3
    case heartbeat = 0xDC
}

/// One NIIMBOT packet: `55 55 cmd len data… checksum AA AA`.
public struct Packet: Equatable, Sendable {
    public var cmd: UInt8
    public var data: [UInt8]

    public init(cmd: UInt8, data: [UInt8] = [1]) {
        self.cmd = cmd
        self.data = data
    }

    public init(_ cmd: Cmd, _ data: [UInt8] = [1]) {
        self.init(cmd: cmd.rawValue, data: data)
    }

    var checksum: UInt8 { data.reduce(cmd ^ UInt8(data.count), ^) }

    public func bytes() -> [UInt8] {
        precondition(data.count <= 0xFF, "packet data too large")
        let frame: [UInt8] = [0x55, 0x55, cmd, UInt8(data.count)] + data + [checksum, 0xAA, 0xAA]
        // The printer expects Connect to be prefixed with 0x03.
        return cmd == Cmd.connect.rawValue ? [0x03] + frame : frame
    }

    /// Big-endian 16-bit value.
    public static func u16(_ n: Int) -> [UInt8] { [UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] }

    /// The reply command the printer sends for `cmd`, or nil if it sends none.
    public static func expectedReply(for cmd: Cmd) -> UInt8? {
        switch cmd {
        case .connect: return 0xC2
        case .setLabelType: return 0x33
        case .setDensity: return 0x31
        case .printStart: return 0x02
        case .printClear: return 0x30
        case .pageStart: return 0x04
        case .printQuantity: return 0x16
        case .printStatus: return 0xB3
        case .setPageSize: return 0x14
        case .pageEnd: return 0xE4
        case .printEnd: return 0xF4
        case .bitmapRow, .emptyRow, .heartbeat: return nil
        }
    }
}
