import Foundation
import LabelCore

/// The app's single print service: one Bluetooth scanner and one serial job queue,
/// used by the window, the CLI (via IPC) and the Print dialog (via CUPS).
@MainActor
final class PrintService: ObservableObject {
    static let shared = PrintService()

    @Published private(set) var state: PrinterState = .idle
    @Published private(set) var progress: (done: Int, total: Int)?
    @Published private(set) var lastResult: JobResult?
    @Published private(set) var queued = 0

    private let scanner = PrinterScanner()
    private lazy var queue = JobQueue(makeLink: { [scanner] in try await scanner.connect() })

    private init() {
        scanner.onState = { [weak self] s in Task { @MainActor in self?.state = s } }
    }

    func print(_ job: LabelJob, onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> JobResult {
        await track { await self.queue.submit(job, progress: self.progressHandler(onProgress)) }
    }

    func print(bitmaps: [Bitmap], settings: PrintSettings) async -> JobResult {
        await track { await self.queue.submit(bitmaps: bitmaps, settings: settings, progress: self.progressHandler()) }
    }

    private func track(_ work: @escaping () async -> JobResult) async -> JobResult {
        queued += 1
        let result = await work()
        queued -= 1
        lastResult = result
        progress = nil
        Log.write("job: printed \(result.printed)/\(result.total) skipped \(result.skipped) \(result.error ?? "ok")")
        return result
    }

    private nonisolated func progressHandler(_ extra: (@Sendable (Int, Int) -> Void)? = nil) -> JobQueue.Progress {
        { done, total in extra?(done, total); Task { @MainActor in
            PrintService.shared.progress = (done, total)
            PrintService.shared.state = .printing(done, total)
        } }
    }

    var statusText: String {
        switch state {
        case .unauthorized: return "Bluetooth access is off. Allow LabelBridge in System Settings › Privacy & Security › Bluetooth."
        case .poweredOff: return "Bluetooth is off."
        case .idle: return "Ready"
        case .searching: return "Looking for the printer…"
        case .found(let name): return "Connected to \(name)"
        case .printing(let d, let t): return "Printing label \(d) of \(t)…"
        case .notFound: return "Printer not found"
        }
    }
}
