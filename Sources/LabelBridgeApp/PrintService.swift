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
    /// The printer's name while it's on and advertising nearby (only tracked while a window watches).
    @Published private(set) var nearby: String?

    private var presence = PresenceTracker()
    private var watchers = 0
    private var presenceTimer: Timer?

    private let scanner = PrinterScanner()
    private lazy var queue = JobQueue(makeLink: { [scanner] in try await scanner.connect() })

    private init() {
        scanner.onState = { [weak self] s in Task { @MainActor in self?.state = s } }
        scanner.onSeen = { [weak self] name in Task { @MainActor in
            self?.presence.saw(name, at: Date())
            self?.refreshPresence()
        } }
    }

    /// Windows that show printer status call this on appear/disappear; scanning runs while any is open.
    func watchPrinter(_ on: Bool) {
        watchers = max(0, watchers + (on ? 1 : -1))
        scanner.watching = watchers > 0
        presenceTimer?.invalidate()
        presenceTimer = nil
        if watchers > 0 {
            presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in PrintService.shared.refreshPresence() }
            }
        }
    }

    private func refreshPresence() {
        let now = presence.current(at: Date())
        if now != nearby { nearby = now }
    }

    /// What the UI shows about the printer.
    var printerStatus: PrinterStatus {
        switch state {
        case .unauthorized:
            return .init(kind: .problem, title: "Bluetooth access needed",
                         detail: "Allow LabelBridge in System Settings › Privacy & Security › Bluetooth.")
        case .poweredOff:
            return .init(kind: .problem, title: "Bluetooth is off", detail: "Turn on Bluetooth in Control Center.")
        case .printing(let d, let t):
            return .init(kind: .busy, title: "Printing label \(d) of \(t)", detail: nearby ?? "D11")
        case .searching, .found:
            return .init(kind: .busy, title: "Connecting…", detail: "Talking to your D11.")
        default:
            if let nearby { return .init(kind: .ready, title: "Ready to print", detail: nearby) }
            return .init(kind: .searching, title: "Looking for your D11…",
                         detail: "Turn it on (hold the power button) and disconnect the NIIMBOT phone app.")
        }
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

struct PrinterStatus: Equatable {
    enum Kind { case ready, searching, busy, problem }
    let kind: Kind
    let title: String
    let detail: String
}
