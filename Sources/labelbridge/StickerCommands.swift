import ArgumentParser
import Foundation
import LabelCore

/// `labelbridge sticker …`: designs from the app's sticker designer (templates, the draft, or .json files).
struct Sticker: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print sticker designs: templates, the designer's draft, or a .json design file.",
        discussion: """
        A DESIGN is one of, in this order: a .json design file (any argument ending in .json or containing /); \
        one of your saved templates, by name in any capitalisation (the most recently saved wins) or by id; \
        `draft` for the design open in the app's sticker designer; or a built-in template, by name or id. \
        `labelbridge sticker list` shows names and ids.

        --text fills the design's text objects in order: give one --text per text object (`sticker list` shows \
        them). Text objects without a --text keep the template's own text, with a warning. \
        `labelbridge sticker export` writes a design file to start from.

        EXAMPLES:
          labelbridge sticker list
          labelbridge sticker print "Names" --text "Dana" --text "Yossi"
          labelbridge sticker print "Icons + text" --text "Oven" --text "Hall" --media transparent
          labelbridge sticker print draft --copies 3
          labelbridge sticker preview "Names" --text "Dana" --text "Yossi" --out /tmp/stickers
          labelbridge sticker export "Icons + text" --out kitchen.json
          labelbridge sticker print kitchen.json --json
          labelbridge sticker alignment --media transparent
        """,
        subcommands: [StickerList.self, StickerPrint.self, StickerPreview.self, StickerExport.self,
                      StickerIcons.self, StickerAlignment.self])
}

/// Prints `error: …` and exits with the bad-input code (2), like `print` does for bad input.
func failBadInput(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    Foundation.exit(ExitCode.badInput)
}

func errorText(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? (error as? ValidationError)?.message ?? "\(error)"
}

/// The app's print offset, so dry runs can warn about ink the offset moves off the label.
var appStickerOffset: StickerOffset {
    let d = LabelOptions.appDefaults
    return StickerOffset(x: d?.double(forKey: "stickerOffsetX") ?? 0, y: d?.double(forKey: "stickerOffsetY") ?? 0)
}

/// The design argument and --text, shared by print, preview and export.
struct DesignOptions: ParsableArguments {
    @Argument(help: "Template name or id, `draft`, or a .json design file.") var design: String
    @Option(name: .shortAndLong, parsing: .unconditionalSingleValue,
            help: "Text for the design's next text object. Repeat for each one; \\n breaks a line.")
    var text: [String] = []

    /// The design with --text applied, its display name, and a warning if some text objects weren't filled.
    func resolve() throws -> (name: String, design: StickerDesign, warnings: [String]) {
        let found = try StickerLibrary.resolve(design, defaults: LabelOptions.appDefaults)
        let filled = try found.design.fillingText(text)
        return (found.name, filled, found.design.unfilledTextWarning(given: text.count).map { [$0] } ?? [])
    }
}

struct StickerList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List sticker templates and the designer's draft, with their text objects.")
    @Flag(help: "Print as JSON.") var json = false

    struct Entry: Encodable {
        let id: String, name: String, kind: String, size: String, shape: String
        let texts: [String], icons: [String]
    }

    func run() throws {
        let d = LabelOptions.appDefaults
        var problems: [String] = []
        var saved: [StickerTemplate] = []
        do { saved = try StickerLibrary.savedTemplates(d) } catch { problems.append(errorText(error)) }
        var draft: StickerDesign?
        do { draft = try StickerLibrary.draft(d) } catch { problems.append(errorText(error)) }
        func entry(_ id: String, _ name: String, _ kind: String, _ design: StickerDesign) -> Entry {
            Entry(id: id, name: name, kind: kind, size: design.size.description,
                  shape: design.shape == .twoCircles ? "two circles" : "rectangle", texts: design.textSlots,
                  icons: design.objects.compactMap { if case .icon(let i) = $0.content { return i.rawValue } else { return nil } })
        }
        var entries = StickerTemplate.builtIn.map { entry($0.id, $0.name, "built-in", $0.design) }
            + saved.map { entry($0.id, $0.name, "saved", $0.design) }
        if let draft { entries.append(entry("draft", "Draft", "draft", draft)) }
        for p in problems { FileHandle.standardError.write(Data("warning: \(p)\n".utf8)) }
        if json {
            let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            print(String(data: try enc.encode(entries), encoding: .utf8)!)
            return
        }
        let width = entries.map(\.name.count).max() ?? 0
        for kind in ["built-in", "saved", "draft"] {
            let group = entries.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            print(kind == "built-in" ? "Templates:" : kind == "saved" ? "\nMy templates:" : "\nDesigner draft (use `draft`):")
            for e in group {
                let contents = (e.texts.map { "\"\($0.replacingOccurrences(of: "\n", with: "\\n"))\"" } + e.icons).joined(separator: ", ")
                print("  " + e.name.padding(toLength: width, withPad: " ", startingAt: 0)
                      + "  \(e.size) mm, \(e.shape)" + (contents.isEmpty ? "" : "  ·  \(contents)"))
                if kind != "draft" { print("  " + String(repeating: " ", count: width) + "  id: \(e.id)") }
            }
        }
        print("\nText objects are in quotes; fill them in order with --text.")
    }
}

struct StickerPrint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "print", abstract: "Print a sticker design.",
        discussion: """
        Prints the design --copies times and waits until done. For the two-circle templates, one copy is one pair. \
        With --json, prints {"ok", "printed", "total", "skipped", "warnings", "error", "failure"} to stdout. \
        Exit codes are the same as `labelbridge print`. The app's print offset (sticker designer › Alignment) is applied.
        """)
    @OptionGroup var design: DesignOptions
    @Option(help: "Copies (pairs, for two-circle designs).") var copies: Int = 1
    @Option(help: "Darkness 1–5 (default: the app's setting).") var density: Int?
    @Option(help: "Label media: gaps or transparent (default: the app's setting).") var media: String?
    @Flag(help: "Render only; don't print.") var dryRun = false
    @Flag(help: "Print the result as JSON.") var json = false

    func run() throws {
        func bad(_ text: String) -> Never {
            finishJob(JobResult(ok: false, printed: 0, total: 0, error: text, failure: .badInput), json: json, unit: "sticker", dryRun: dryRun)
        }
        let job: StickerJob, extra: [String]
        do {
            let resolved = try design.resolve()
            job = StickerJob(design: resolved.design,
                             settings: try LabelOptions.settings(density: density, media: media, copies: copies), source: .cli)
            extra = resolved.warnings
        } catch { bad(errorText(error)) }
        if dryRun {
            do {
                let warnings = try job.render(offset: appStickerOffset).warnings
                finishJob(JobResult(ok: true, printed: 0, total: job.settings.copies, warnings: extra + warnings), json: json, unit: "sticker", dryRun: true)
            } catch { bad(errorText(error)) }
        }
        var result = sendJob(.printSticker(job), json: json, unit: "sticker")
        result.warnings = extra + result.warnings
        finishJob(result, json: json, unit: "sticker", dryRun: false)
    }
}

struct StickerPreview: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview", abstract: "Write a sticker design as a PNG without printing.",
        discussion: "The PNG is the 12 mm print band, as it prints (without the app's print offset). Warnings go to stderr.")
    @OptionGroup var design: DesignOptions
    @Option(help: "Output directory.") var out: String = "."

    func run() throws {
        let name: String, rendered: (bitmap: Bitmap, warnings: [String]), extra: [String]
        do {
            let resolved = try design.resolve()
            (name, extra) = (resolved.name, resolved.warnings)
            rendered = try StickerJob(design: resolved.design, settings: PrintSettings(), source: .cli).render()
        } catch { failBadInput(errorText(error)) }
        let dir = (out as NSString).expandingTildeInPath
        let slug = name.lowercased().replacingOccurrences(of: ".json", with: "")
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let url = URL(fileURLWithPath: dir).appendingPathComponent("sticker-\(slug.isEmpty ? "design" : slug).png")
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try rendered.bitmap.pngData().write(to: url)
        } catch { failBadInput("Can't write \(url.path): \(error.localizedDescription)") }
        print(url.path)
        for w in extra + rendered.warnings { FileHandle.standardError.write(Data("warning: \(w)\n".utf8)) }
    }
}

struct StickerExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Write a design as JSON, to edit and print with `sticker print FILE`.",
        discussion: """
        Sizes and positions are millimetres from the label's top-left corner; size is {widthMM, lengthMM}. \
        Each object is {"content": {"text": "…"} or {"icon": "…"}, "frame": {x, y, width, height}, "style": {…}}. \
        "id" and "style" may be left out; ids must differ if present. Style: fontName, bold, italic, alignment \
        (center, leading, trailing), fontSizePoints (1–72; leave out to fit the object). Shape "twoCircles" needs size 14x28.
        """)
    @OptionGroup var design: DesignOptions
    @Option(help: "Output file (default: stdout).") var out: String?

    func run() throws {
        let data: Data
        do { data = try StickerLibrary.export(try design.resolve().design) } catch { failBadInput(errorText(error)) }
        guard let out else { print(String(data: data, encoding: .utf8)!); return }
        let path = (out as NSString).expandingTildeInPath
        do { try data.write(to: URL(fileURLWithPath: path)) }
        catch { failBadInput("Can't write \(path): \(error.localizedDescription)") }
        print(path)
    }
}

struct StickerIcons: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "icons", abstract: "List the icons a design can use.")
    func run() {
        let width = StickerIcon.allCases.map(\.rawValue.count).max() ?? 0
        for icon in StickerIcon.allCases { print(icon.rawValue.padding(toLength: width, withPad: " ", startingAt: 0) + "  \(icon.title)") }
    }
}

struct StickerAlignment: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alignment", abstract: "Print an alignment test to check where ink lands on a sticker roll.",
        discussion: """
        For two-circle rolls, prints a ring and a cross in the middle of each circle (a dot marks the left one). \
        For rectangles, a cross in the middle and an outline around the printable area. If the cross is off-centre, \
        set the offset in the app (sticker designer › Alignment) and test again.
        """)
    @Argument(help: "Template whose paper to test (default: Blank circles).") var design: String = "blank-circles"
    @Option(help: "Darkness 1–5 (default: the app's setting).") var density: Int?
    @Option(help: "Label media: gaps or transparent (default: the app's setting).") var media: String?
    @Flag(help: "Render only; don't print.") var dryRun = false
    @Flag(help: "Print the result as JSON.") var json = false

    func run() throws {
        let job: StickerJob
        do {
            job = StickerJob(design: try StickerLibrary.resolve(design, defaults: LabelOptions.appDefaults).design,
                             settings: try LabelOptions.settings(density: density, media: media, copies: 1),
                             source: .cli, alignmentTest: true)
        } catch {
            finishJob(JobResult(ok: false, printed: 0, total: 0, error: errorText(error), failure: .badInput),
                      json: json, unit: "alignment test", dryRun: dryRun)
        }
        if dryRun {
            let warnings = (try? job.render(offset: appStickerOffset).warnings) ?? []
            finishJob(JobResult(ok: true, printed: 0, total: 1, warnings: warnings), json: json, unit: "alignment test", dryRun: true)
        }
        finishJob(sendJob(.printSticker(job), json: json, unit: "test"), json: json, unit: "alignment test", dryRun: false)
    }
}
