import AppKit
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
    private var presenceTimer: Timer?

    private let scanner = PrinterScanner()
    private lazy var queue = JobQueue(makeLink: { [scanner] in try await scanner.connect() },
                                      makeSession: { PrintSession(link: $0, log: { Log.write($0) }) })

    private init() {
        scanner.onState = { [weak self] s in Task { @MainActor in self?.state = s } }
        scanner.onSeen = { [weak self] name in Task { @MainActor in
            self?.presence.saw(name, at: Date())
            self?.refreshPresence()
        } }
        observeWindows()
    }

    /// Scans for the printer exactly while one of the app's windows is on screen.
    private func observeWindows() {
        let names: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                // After willClose the window is still listed; look again on the next turn of the run loop.
                DispatchQueue.main.async { MainActor.assumeIsolated { PrintService.shared.updateWatching() } }
            }
        }
    }

    func updateWatching() {
        let windowOpen = !NSApp.isHidden && NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard windowOpen != scanner.watching else { return }
        scanner.watching = windowOpen
        presenceTimer?.invalidate()
        presenceTimer = nil
        if windowOpen {
            presenceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in PrintService.shared.refreshPresence() }
            }
        }
        Log.write("printer scan \(windowOpen ? "on" : "off")")
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
