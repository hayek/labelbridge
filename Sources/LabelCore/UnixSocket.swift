import Foundation

public enum IPCError: Error { case socket(String), closed }

/// Serves newline-delimited JSON requests on a Unix domain socket (owner-only, mode 0600).
public final class IPCServer: @unchecked Sendable {
    public typealias Handler = @Sendable (IPCRequest, _ send: @escaping @Sendable (IPCMessage) -> Void) async -> Void
    private let path: String
    private let fd: Int32
    private let handler: Handler
    private var running = true

    public init(path: String, handler: @escaping Handler) throws {
        self.path = path
        self.handler = handler
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.socket("socket") }
        var addr = try sockaddrUnix(path)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0 else { close(fd); throw IPCError.socket("bind \(errno)") }
        chmod(path, 0o600)
        guard listen(fd, 8) == 0 else { close(fd); throw IPCError.socket("listen") }
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    public func stop() {
        running = false
        shutdown(fd, SHUT_RDWR)
        close(fd)
        unlink(path)
    }

    private func acceptLoop() {
        while running {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { if running { continue } else { return } }
            let handler = self.handler
            Thread.detachNewThread {
                guard let line = readLine(client), let request = try? IPCCoding.decode(IPCRequest.self, from: line) else { close(client); return }
                let done = DispatchSemaphore(value: 0)
                let send: @Sendable (IPCMessage) -> Void = { msg in if let d = try? IPCCoding.encode(msg) { writeAll(client, d) } }
                Task { await handler(request, send); done.signal() }
                done.wait()
                close(client)
            }
        }
    }
}

/// Sends one request and waits for the final message.
public struct IPCClient: Sendable {
    let path: String
    public init(path: String = IPCPaths.socketURL.path) { self.path = path }

    @discardableResult
    public func send(_ request: IPCRequest, onProgress: (Int, Int) -> Void) throws -> IPCMessage {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCError.socket("socket") }
        defer { close(fd) }
        var addr = try sockaddrUnix(path)
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0 else { throw IPCError.socket("connect \(errno)") }
        writeAll(fd, try IPCCoding.encode(request))
        while let line = readLine(fd) {
            let msg = try IPCCoding.decode(IPCMessage.self, from: line)
            if case .progress(let d, let t) = msg { onProgress(d, t) } else { return msg }
        }
        throw IPCError.closed
    }
}

private func sockaddrUnix(_ path: String) throws -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw IPCError.socket("path too long") }
    withUnsafeMutableBytes(of: &addr.sun_path) { buf in
        for (i, b) in bytes.enumerated() { buf[i] = b }
        buf[bytes.count] = 0
    }
    return addr
}

private func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
        var off = 0
        while off < raw.count {
            let n = write(fd, raw.baseAddress! + off, raw.count - off)
            if n <= 0 { return }
            off += n
        }
    }
}

/// Reads up to and including the next newline (nil at EOF).
private func readLine(_ fd: Int32) -> Data? {
    var line = Data()
    var byte: UInt8 = 0
    while read(fd, &byte, 1) == 1 {
        line.append(byte)
        if byte == UInt8(ascii: "\n") { return line }
    }
    return line.isEmpty ? nil : line
}
