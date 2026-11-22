import Foundation

public enum JobSource: String, Codable, Sendable { case window, cli, cups }

/// A batch of text labels: one label per item.
public struct LabelJob: Codable, Sendable {
    public var items: [String]
    public var size: LabelSize
    public var style: TextStyle
    public var settings: PrintSettings
    public var source: JobSource

    public init(items: [String], size: LabelSize, style: TextStyle, settings: PrintSettings, source: JobSource) {
        self.items = items
        self.size = size
        self.style = style
        self.settings = settings
        self.source = source
    }
}

public enum JobFailure: String, Codable, Sendable { case badInput, notFound, busy, failedMidJob, timeout, appUnavailable }

public struct JobResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var printed: Int
    public var total: Int
    public var skipped: Int
    public var warnings: [String]
    public var error: String?
    public var failure: JobFailure?

    public init(ok: Bool, printed: Int, total: Int, skipped: Int = 0, warnings: [String] = [], error: String? = nil, failure: JobFailure? = nil) {
        self.ok = ok
        self.printed = printed
        self.total = total
        self.skipped = skipped
        self.warnings = warnings
        self.error = error
        self.failure = failure
    }
}

/// Runs print jobs strictly one after another on fresh printer connections.
public actor JobQueue {
    public typealias Progress = @Sendable (Int, Int) -> Void
    private let makeLink: @Sendable () async throws -> PrinterLink
    private let makeSession: @Sendable (PrinterLink) -> PrintSession
    private var tail: Task<Void, Never>?

    public init(makeLink: @escaping @Sendable () async throws -> PrinterLink,
                makeSession: @escaping @Sendable (PrinterLink) -> PrintSession = { PrintSession(link: $0) }) {
        self.makeLink = makeLink
        self.makeSession = makeSession
    }

    /// Renders and prints a text job.
    public func submit(_ job: LabelJob, progress: @escaping Progress) async -> JobResult {
        let parsed = Batch.items(from: job.items)
        guard !parsed.items.isEmpty else {
            return JobResult(ok: false, printed: 0, total: 0, skipped: parsed.skipped, error: "No labels to print.", failure: .badInput)
        }
        var warnings: [String] = []
        let bitmaps = parsed.items.map { item -> Bitmap in
            let r = TextRenderer.render(item, size: job.size, style: job.style)
            if let w = r.warning { warnings.append(w) }
            return r.bitmap
        }
        var result = await submit(bitmaps: bitmaps, settings: job.settings, progress: progress)
        result.skipped = parsed.skipped
        result.warnings = warnings + result.warnings
        return result
    }

    /// Prints pre-rendered labels (used for Print-dialog jobs). Waits for earlier jobs to finish first.
    public func submit(bitmaps: [Bitmap], settings: PrintSettings, progress: @escaping Progress) async -> JobResult {
        let previous = tail
        let work = Task { [makeLink, makeSession] () -> JobResult in
            await previous?.value
            return await Self.run(bitmaps: bitmaps, settings: settings, makeLink: makeLink, makeSession: makeSession, progress: progress)
        }
        tail = Task { _ = await work.value }
        return await work.value
    }

    private static func run(bitmaps: [Bitmap], settings: PrintSettings,
                            makeLink: @Sendable () async throws -> PrinterLink,
                            makeSession: @Sendable (PrinterLink) -> PrintSession,
                            progress: Progress) async -> JobResult {
        let total = bitmaps.count * settings.copies
        let pages = bitmaps.map(RowEncoder.encode)
        var link: PrinterLink?
        do {
            link = try await makeLink()
            let printed = try await makeSession(link!).run(pages: pages, settings: settings, progress: progress)
            await link?.close()
            return JobResult(ok: true, printed: printed, total: total)
        } catch {
            await link?.close()
            return failureResult(error, total: total)
        }
    }

    static func failureResult(_ error: Error, total: Int) -> JobResult {
        switch error as? PrintError {
        case .notFound?:
            return JobResult(ok: false, printed: 0, total: total, error: "Printer not found. Turn on the D11 and disconnect the NIIMBOT phone app.", failure: .notFound)
        case .busy?:
            return JobResult(ok: false, printed: 0, total: total, error: "The printer is busy or connected to another device.", failure: .busy)
        case .failedMidJob(let printed)?:
            return JobResult(ok: false, printed: printed, total: total, error: "Printing stopped after \(printed) of \(total) labels.", failure: .failedMidJob)
        default:
            return JobResult(ok: false, printed: 0, total: total, error: "The printer did not respond.", failure: .timeout)
        }
    }
}
