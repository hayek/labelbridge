import AppKit
import ArgumentParser
import Foundation
import LabelCore

struct LabelBridgeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "labelbridge",
        abstract: "Print labels to a NIIMBOT Bluetooth label printer through LabelBridge.app.",
        discussion: """
        One label per argument (or per line with --file / stdin). Type \\n inside a label for a line break.
        Exit codes: 0 printed, 2 bad input, 3 printer not found or busy, 4 printing failed, 5 LabelBridge.app not available.
        """,
        subcommands: [Print.self, Preview.self, Status.self, Sizes.self],
        defaultSubcommand: Print.self)
}

/// Options shared by print and preview. Defaults come from the app's settings.
struct LabelOptions: ParsableArguments {
    @Argument(help: "Label texts. Use - to read lines from stdin.") var items: [String] = []
    @Option(name: .shortAndLong, help: "Read labels from a file, one per line.") var file: String?
    @Option(help: "Label size in mm, e.g. 50x15.") var size: String?
    @Option(help: "Darkness 1–5.") var density: Int?
    @Option(help: "Copies of each label.") var copies: Int = 1
    @Option(help: "center, leading or trailing.") var align: String?
    @Option(help: "Font family name, e.g. \"Arial Hebrew\".") var font: String?
    @Flag(help: "Bold text.") var bold = false

    static let appDefaults = UserDefaults(suiteName: IPCPaths.bundleID)

    func lines() throws -> [String] {
        var lines: [String] = []
        if let file {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { throw ValidationError("Can't read \(file) as UTF-8 text.") }
            lines += Batch.lines(from: text)
        }
        for item in items {
            if item == "-" { while let l = Swift.readLine(strippingNewline: true) { lines.append(l) } } else { lines.append(item) }
        }
        return lines
    }

    func job() throws -> LabelJob {
        let d = Self.appDefaults
        guard let labelSize = size.map({ LabelSize(parsing: $0) }) ?? d?.string(forKey: "labelSize").flatMap(LabelSize.init(parsing:)) ?? .defaultSize else {
            throw ValidationError("Invalid --size \(size ?? ""). Use width x length in mm, e.g. 15x50.")
        }
        let alignment = try align.map { a -> Alignment in
            guard let v = Alignment(rawValue: a) else { throw ValidationError("--align must be center, leading or trailing.") }
            return v
        } ?? d?.string(forKey: "alignment").flatMap(Alignment.init(rawValue:)) ?? .center
        let style = TextStyle(fontName: font ?? d?.string(forKey: "fontName"), bold: bold || (d?.bool(forKey: "bold") ?? false), alignment: alignment)
        let dens = density ?? (d?.object(forKey: "density") as? Int) ?? 3
        guard (1...5).contains(dens) else { throw ValidationError("--density must be 1–5.") }
        guard (1...99).contains(copies) else { throw ValidationError("--copies must be 1–99.") }
        return LabelJob(items: try lines(), size: labelSize, style: style, settings: PrintSettings(density: dens, copies: copies), source: .cli)
    }
}

struct Print: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print labels (default command).")
    @OptionGroup var options: LabelOptions
    @Flag(help: "Render only; don't print.") var dryRun = false
    @Flag(help: "Print the result as JSON.") var json = false

    func run() throws {
        let job: LabelJob
        do { job = try options.job() } catch let e as ValidationError {
            finish(JobResult(ok: false, printed: 0, total: 0, error: e.message, failure: .badInput))
        }
        if dryRun { finish(dryRunResult(job)) }
        if Batch.items(from: job.items).items.isEmpty {
            finish(JobResult(ok: false, printed: 0, total: 0, error: "No labels to print.", failure: .badInput))
        }
        var lastProgress = (done: 0, total: 0)
        do {
            let message = try AppConnection.send(.print(job)) { done, total in
                lastProgress = (done, total)
                if !json { FileHandle.standardError.write(Data("Printing label \(done) of \(total)…\n".utf8)) }
            }
            guard case .result(let r) = message else { throw IPCError.closed }
            finish(r)
        } catch IPCError.notRunning {
            finish(JobResult(ok: false, printed: 0, total: 0, error: AppConnection.unavailableMessage, failure: .appUnavailable))
        } catch {
            // The app received the job but went away (quit or crashed) before answering.
            let printed = lastProgress.done            // progress is reported after each label finishes
            finish(JobResult(ok: false, printed: printed, total: lastProgress.total,
                             error: "LabelBridge stopped while printing, after \(printed) of \(lastProgress.total) labels.", failure: .failedMidJob))
        }
    }

    private func dryRunResult(_ job: LabelJob) -> JobResult {
        let parsed = Batch.items(from: job.items)
        let warnings = parsed.items.compactMap { TextRenderer.render($0, size: job.size, style: job.style).warning }
        return JobResult(ok: !parsed.items.isEmpty, printed: 0, total: parsed.items.count * job.settings.copies,
                         skipped: parsed.skipped, warnings: warnings, error: parsed.items.isEmpty ? "No labels to print." : nil,
                         failure: parsed.items.isEmpty ? .badInput : nil)
    }

    private func finish(_ r: JobResult) -> Never {
        if json {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(data: try! enc.encode(r), encoding: .utf8)!)
        } else {
            for w in r.warnings { FileHandle.standardError.write(Data("warning: \(w)\n".utf8)) }
            if r.ok { print(dryRun ? "OK: \(r.total) labels would print" + (r.skipped > 0 ? " (\(r.skipped) blank skipped)" : "") : "Printed \(r.printed) labels") }
            else { FileHandle.standardError.write(Data("error: \(r.error ?? "failed")\n".utf8)) }
        }
        Foundation.exit(ExitCode.for(r))
    }
}

struct Preview: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Write label images (PNG) without printing.")
    @OptionGroup var options: LabelOptions
    @Option(help: "Output directory.") var out: String = "."

    func run() throws {
        let job = try options.job()
        let items = Batch.items(from: job.items).items
        guard !items.isEmpty else { throw ValidationError("No labels.") }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        for (i, item) in items.enumerated() {
            let r = TextRenderer.render(item, size: job.size, style: job.style)
            let url = URL(fileURLWithPath: out).appendingPathComponent(String(format: "label-%03d.png", i + 1))
            try r.bitmap.pngData().write(to: url)
            print(url.path + (r.warning.map { "  (\($0))" } ?? ""))
        }
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show whether LabelBridge.app and the printer are available.")
    @Flag(help: "Print as JSON.") var json = false

    func run() throws {
        let reply = try? AppConnection.send(.status, launch: false, onProgress: { _, _ in })
        guard case .status(let s)? = reply else {
            if json { print(#"{"app":false}"#) } else { print("LabelBridge.app is not running.") }
            Foundation.exit(ExitCode.appUnavailable)
        }
        if json {
            let enc = JSONEncoder(); enc.outputFormatting = .sortedKeys
            print(String(data: try enc.encode(s), encoding: .utf8)!)
        } else {
            print("LabelBridge \(s.appVersion) · printer: \(s.printer) · jobs queued: \(s.queued)")
        }
    }
}

struct Sizes: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List built-in label sizes (width x length, mm).")
    func run() { for s in LabelSize.builtIn { print(s.description + (s == .defaultSize ? "  (default)" : "")) } }
}
