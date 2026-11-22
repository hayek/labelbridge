import Foundation

public struct StatusInfo: Codable, Sendable {
    public var appVersion: String
    public var printer: String
    public var queued: Int
    public init(appVersion: String, printer: String, queued: Int) {
        self.appVersion = appVersion
        self.printer = printer
        self.queued = queued
    }
}

/// CLI → app.
public enum IPCRequest: Codable, Sendable {
    case print(LabelJob)
    case status
}

/// App → CLI. A print request gets zero or more `progress` messages, then one `result`.
public enum IPCMessage: Codable, Sendable {
    case progress(Int, Int)
    case result(JobResult)
    case status(StatusInfo)
}

/// Newline-delimited JSON.
public enum IPCCoding {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var d = try JSONEncoder().encode(value)   // JSON escapes newlines inside strings
        d.append(UInt8(ascii: "\n"))
        return d
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line.last == UInt8(ascii: "\n") ? line.dropLast() : line)
    }
}

public enum IPCPaths {
    public static let bundleID = "io.github.hayek.labelbridge"
    public static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LabelBridge/labelbridge.sock")
    }
}

public enum ExitCode {
    public static let ok: Int32 = 0, badInput: Int32 = 2, printerUnavailable: Int32 = 3, failed: Int32 = 4, appUnavailable: Int32 = 5

    public static func `for`(_ r: JobResult) -> Int32 {
        if r.ok { return ok }
        switch r.failure {
        case .badInput?: return badInput
        case .notFound?, .busy?: return printerUnavailable
        case .appUnavailable?: return appUnavailable
        default: return failed
        }
    }
}
