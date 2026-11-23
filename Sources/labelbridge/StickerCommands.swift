import ArgumentParser
import Foundation
import LabelCore

/// `labelbridge sticker …`: designs from the app's sticker designer (templates, the draft, or .json files).
struct Sticker: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print sticker designs: templates, the designer's draft, or a .json design file.",
        discussion: """
        A DESIGN is a template name or id (`labelbridge sticker list`), `draft` for the design open in the app's \
        sticker designer, or the path of a .json design file (`labelbridge sticker export` writes one to start from). \
        Use --text to fill the design's text objects in order, for example the two circles of the "Names" template.

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

/// The design argument and --text, shared by print, preview and export.
struct DesignOptions: ParsableArguments {
    @Argument(help: "Template name or id, `draft`, or a .json design file.") var design: String
    @Option(name: .shortAndLong, help: "Text for the design's text objects, in order. Repeat for each one; \\n breaks a line.")
    var text: [String] = []

    func resolve() throws -> (name: String, design: StickerDesign) {
        do {
            let found = try StickerLibrary.resolve(design, defaults: LabelOptions.appDefaults)
            return (found.name, try found.design.fillingText(text))
        } catch let e as LocalizedError {
            throw ValidationError(e.errorDescription ?? "\(e)")
        }
    }
}

struct StickerList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List sticker templates and the designer's draft.")
    @Flag(help: "Print as JSON.") var json = false

    struct Entry: Encodable {
        let id: String, name: String, kind: String, size: String, shape: String
        let texts: [String], icons: [String]
    }

    func run() throws {
        let d = LabelOptions.appDefaults
        let saved = (try? StickerLibrary.savedTemplates(d)) ?? []
        func entry(_ id: String, _ name: String, _ kind: String, _ design: StickerDesign) -> Entry {
            Entry(id: id, name: name, kind: kind, size: design.size.description,
                  shape: design.shape == .twoCircles ? "two circles" : "rectangle", texts: design.textSlots,
                  icons: design.objects.compactMap { if case .icon(let i) = $0.content { return i.rawValue } else { return nil } })
        }
        var entries = StickerTemplate.builtIn.map { entry($0.id, $0.name, "built-in", $0.design) }
            + saved.map { entry($0.id, $0.name, "saved", $0.design) }
        if let draft = StickerLibrary.draft(d) { entries.append(entry("draft", "Draft", "draft", draft)) }
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
            }
        }
    }
}

struct StickerPrint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "print", abstract: "Print a sticker design.",
        discussion: """
        Prints the design --copies times and waits until done. For the two-circle templates, one copy is one pair. \
        With --json, prints {"ok", "printed", "total", "warnings", "error"} to stdout. Exit codes are the same as `labelbridge print`. \
        The app's print offset (sticker designer › Alignment) is applied.
        """)
    @OptionGroup var design: DesignOptions
    @Option(help: "Copies (pairs, for two-circle designs).") var copies: Int = 1
    @Option(help: "Darkness 1–5 (default: the app's setting).") var density: Int?
    @Option(help: "Label media: gaps or transparent (default: the app's setting).") var media: String?
    @Flag(help: "Render only; don't print.") var dryRun = false
    @Flag(help: "Print the result as JSON.") var json = false

    func run() throws {
        let job: StickerJob
        do {
            job = StickerJob(design: try design.resolve().design,
                             settings: try LabelOptions.settings(density: density, media: media, copies: copies), source: .cli)
        } catch let e as ValidationError {
            finishJob(JobResult(ok: false, printed: 0, total: 0, error: e.message, failure: .badInput), json: json, unit: "sticker", dryRun: dryRun)
        }
        if dryRun {
            do {
                let warnings = try job.render().warnings
                finishJob(JobResult(ok: true, printed: 0, total: job.settings.copies, warnings: warnings), json: json, unit: "sticker", dryRun: true)
            } catch {
                finishJob(JobResult(ok: false, printed: 0, total: 0, error: error.localizedDescription, failure: .badInput),
                          json: json, unit: "sticker", dryRun: true)
            }
        }
        finishJob(sendJob(.printSticker(job), json: json, unit: "sticker"), json: json, unit: "sticker", dryRun: false)
    }
}

struct StickerPreview: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview", abstract: "Write a sticker design as a PNG without printing.",
        discussion: "The PNG is the 12 mm print band, exactly as it prints. Warnings go to stderr.")
    @OptionGroup var design: DesignOptions
    @Option(help: "Output directory.") var out: String = "."

    func run() throws {
        let (name, resolved) = try design.resolve()
        let rendered: (bitmap: Bitmap, warnings: [String])
        do { rendered = try StickerJob(design: resolved, settings: PrintSettings(), source: .cli).render() }
        catch { throw ValidationError(error.localizedDescription) }
        try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
        let slug = name.lowercased().replacingOccurrences(of: ".json", with: "")
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let url = URL(fileURLWithPath: out).appendingPathComponent("sticker-\(slug.isEmpty ? "design" : slug).png")
        try rendered.bitmap.pngData().write(to: url)
        print(url.path)
        for w in rendered.warnings { FileHandle.standardError.write(Data("warning: \(w)\n".utf8)) }
    }
}

struct StickerExport: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export", abstract: "Write a design as JSON, to edit and print with `sticker print FILE`.",
        discussion: """
        Sizes and positions are millimetres from the label's top-left corner; size is {widthMM, lengthMM}. \
        Each object is {"content": {"text": "…"} or {"icon": "…"}, "frame": {x, y, width, height}, "style": {…}}. \
        "id" and "style" may be left out. Style: fontName, bold, italic, alignment (center, leading, trailing), \
        fontSizePoints (1–72; leave out to fit the object). Shape "twoCircles" needs size 14x28.
        """)
    @OptionGroup var design: DesignOptions
    @Option(help: "Output file (default: stdout).") var out: String?

    func run() throws {
        let data = try StickerLibrary.export(try design.resolve().design)
        if let out {
            try data.write(to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
            print(out)
        } else {
            print(String(data: data, encoding: .utf8)!)
        }
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
        If they're off-centre, set the offset in the app (sticker designer › Alignment) and test again.
        """)
    @Argument(help: "Template whose paper to test (default: Blank circles).") var design: String = "blank-circles"
    @Option(help: "Darkness 1–5 (default: the app's setting).") var density: Int?
    @Option(help: "Label media: gaps or transparent (default: the app's setting).") var media: String?
    @Flag(help: "Print the result as JSON.") var json = false

    func run() throws {
        let job: StickerJob
        do {
            job = StickerJob(design: try DesignOptions.parse([design]).resolve().design,
                             settings: try LabelOptions.settings(density: density, media: media, copies: 1),
                             source: .cli, alignmentTest: true)
        } catch let e as ValidationError {
            finishJob(JobResult(ok: false, printed: 0, total: 0, error: e.message, failure: .badInput), json: json, unit: "alignment test", dryRun: false)
        }
        finishJob(sendJob(.printSticker(job), json: json, unit: "test"), json: json, unit: "alignment test", dryRun: false)
    }
}
