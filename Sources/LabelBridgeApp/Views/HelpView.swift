import SwiftUI
import LabelCore

/// Help → LabelBridge Help: topics on the left, the selected topic on the right.
struct HelpView: View {
    enum Topic: String, CaseIterable, Identifiable {
        case start = "Getting Started"
        case window = "Printing Labels"
        case designer = "Sticker Designer"
        case cli = "Command Line"
        case agents = "AI Agents"
        case dialog = "Print Dialog"
        case sizes = "Label Sizes"
        case trouble = "Troubleshooting"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .start: return "sparkles"
            case .window: return "tag"
            case .designer: return "square.and.pencil"
            case .cli: return "terminal"
            case .agents: return "cpu"
            case .dialog: return "printer"
            case .sizes: return "ruler"
            case .trouble: return "wrench.and.screwdriver"
            }
        }
    }

    @State private var topic: Topic? = .start

    /// What users paste into an AI assistant's instructions (Help › AI Agents).
    static let agentInstructions = """
    To print labels on my NIIMBOT label printer, use the `labelbridge` command:
    - Text labels: `labelbridge print --json "First label" "Second label"` (one label per argument; \\n inside a label breaks the line).
    - Stickers: run `labelbridge sticker list` to see the templates, then `labelbridge sticker print --json "TEMPLATE" --text "…" --text "…"`. Each --text fills the template's next text object; for two-circle templates each copy is one pair of circles.
    - Check first without printing: add `--dry-run`. Preview as PNG: `labelbridge preview …` or `labelbridge sticker preview … --out DIR`.
    - Run `labelbridge help sticker` for design files and more options.
    """

    var body: some View {
        NavigationSplitView {
            List(Topic.allCases, selection: $topic) { t in
                Label(t.rawValue, systemImage: t.symbol).tag(t)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text((topic ?? .start).rawValue).font(.largeTitle.weight(.bold))
                    page(topic ?? .start)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder private func page(_ t: Topic) -> some View {
        switch t {
        case .start:
            P("LabelBridge prints labels and stickers to a NIIMBOT D11 or D110 over Bluetooth, from this app, from the command line, and from any app's Print dialog.")
            Steps([
                "Turn the D11 on: hold the power button until the light comes on.",
                "Disconnect the NIIMBOT phone app. The printer accepts only one Bluetooth connection at a time.",
                "Wait for **Ready to print** in the toolbar of the LabelBridge window.",
                "Type or paste your labels, one per line, and click **Print**.",
            ])
            P("Setup added the printer **NIIMBOT D11 (Bluetooth)** to macOS and installed the `labelbridge` command. To run it again, choose LabelBridge › Settings › Repair Setup.")
        case .window:
            P("Type or paste labels on the left, **one label per line**. Blank lines are skipped. Each label's text is sized to fill the label.")
            P("Type `\\n` inside a line to break that label into two lines, for example `Spices\\nTop shelf`.")
            P("The middle shows a preview of each label at its real proportions. A ⚠︎ means the text was too long and will be shortened with “…”.")
            P("On the right, choose the label size, copies, darkness, font, bold and alignment. LabelBridge remembers them, and the command line uses them as its defaults.")
            P("Any language works, including Hebrew and Arabic. Alignment follows the text: “start” is the right side for right-to-left text.")
            P("Press **⌘P** to print.")
        case .designer:
            P("Choose **Sticker designer** at the top of the main window, then pick a template from **Templates**. The circular templates match two 14 mm circles on a 14 × 28 mm feed unit.")
            P("Use **Add Text** or **Add Icon** to add objects. Click an object to select it, drag it to move it, and drag the blue bottom-right handle to resize it. The inspector also accepts exact position and dimensions in millimetres.")
            P("Each circle can contain several independent text and icon objects. Use the **Objects** list to select overlapping objects, or **Delete object** to remove one. **Undo** and **Redo** reverse edits.")
            P("Select a text object and edit its words in **Text content** on the right. You can change the font, bold, italic and alignment. **Auto-fit text** sizes the words to the object; turn it off to set **Font size** from 1–72 pt. The preview warns when the text does not fit.")
            P("Your draft is saved automatically. **Save Template** adds a named design to **My Templates**. Select **Transparent** for transparent rolls; **Print 1 Pair** prints both circles as one feed unit.")
            P("Circle outlines and selection handles never print. The preview uses the same bitmap as printing and warns if ink is outside the sticker or the printer's 12 mm print band.")
            Text("Alignment").font(.title3.weight(.semibold)).padding(.top, 6)
            P("To check where your printer puts ink on a sticker roll, click **Print Alignment Test** under **Alignment**. For paired circles it prints a ring and a cross in the middle of each circle; a dot marks the left circle, so hold the sticker the way the designer shows it.")
            P("If the ring is off-centre, set **Move right** or **Move down** by that much (in mm; negative moves left or up) and print the test again. The offset applies to every sticker you print, from the window and from the command line. Previews don't include it.")
            Text("From the command line").font(.title3.weight(.semibold)).padding(.top, 6)
            P("`labelbridge sticker` prints the built-in templates, your saved templates and the current draft. `--text` fills the design's text objects in order. See **Command Line**.")
        case .cli:
            P("The `labelbridge` command prints labels from Terminal and scripts. It talks to LabelBridge, which opens in the background if it isn't running.")
            Code("""
            labelbridge print "Dana" "Yossi" "محمد"    # one label per argument
            labelbridge print --file names.txt          # one label per line
            cat names.txt | labelbridge print -         # from stdin
            labelbridge print --json "Dana"             # machine-readable result
            labelbridge preview "Dana" --out /tmp/labels
            labelbridge status
            labelbridge sizes
            """)
            Text("Stickers").font(.title3.weight(.semibold)).padding(.top, 6)
            P("`labelbridge sticker` prints designs from the sticker designer: a template name, `draft` for the design open in the designer, or a `.json` design file. `--text` replaces the design's text objects in order, so one template prints any names or captions.")
            Code("""
            labelbridge sticker list                         # templates and the draft
            labelbridge sticker print "Names" --text "Dana" --text "Yossi"
            labelbridge sticker print "Icons + text" --text "Oven" --text "Hall"
            labelbridge sticker print draft --copies 3 --media transparent
            labelbridge sticker preview "Names" --text "Dana" --out /tmp/stickers
            labelbridge sticker export "Names" --out names.json   # edit, then:
            labelbridge sticker print names.json
            labelbridge sticker icons                        # icon names for .json files
            labelbridge sticker alignment                    # alignment test print
            """)
            P("Save a design with **Save Template** in the designer, and it's available by name from the command line. For two-circle templates, each copy is one pair.")
            Text("Full reference").font(.title3.weight(.semibold)).padding(.top, 6)
            P("This is the built-in help of the installed command (`labelbridge --help`).")
            Code(CLIHelp.text)
        case .agents:
            P("AI assistants that can run shell commands, such as Claude Code, can print labels with `labelbridge`. Add this line to the assistant's instructions (for example `CLAUDE.md`):")
            Code(Self.agentInstructions)
            P("The JSON result says how many labels or stickers printed, and the exit code says what went wrong: 2 means bad input (for example an unknown template), 3 means the printer is off or busy, 5 means LabelBridge couldn't be reached.")
            P("Your saved sticker templates are available to the assistant by name, so you can design a sticker once and ask it to print it with different text.")
            P("Some assistants run commands in a sandbox. If you get exit code **5**, allow access to `~/Library/Application Support/LabelBridge/` and to opening apps, or run the command outside the sandbox.")
        case .dialog:
            P("In any app, choose **File › Print**, pick **NIIMBOT D11 (Bluetooth)**, and choose a label size under **Paper Size**. Each page becomes one label, fitted and centred.")
            P("LabelBridge must be running. To print from other apps without opening LabelBridge first, turn on **Open at login** in LabelBridge › Settings.")
            P("If a Print-dialog job fails (for example, the printer is off), LabelBridge shows a notification.")
        case .sizes:
            P("Built-in sizes, width × length in mm:")
            Code(LabelSize.builtIn.map { "\($0.description)" + ($0 == .defaultSize ? "   (default)" : "") }.joined(separator: "\n"))
            P("On the command line, any other size works with `--size WxL`, for example `--size 12x30`.")
            P("For TT14×28-220 transparent rolls, choose **14 × 28 mm** and **Media: Transparent**. The roll contains 220 labels. The command-line equivalent is `--size 14x28 --media transparent`. Print-dialog jobs also use the window's Media setting.")
            P("The D11's print head is 12 mm wide, so wider labels print in a 12 mm band in the middle. LabelBridge leaves 2 mm empty at each end so nothing is cut off.")
        case .trouble:
            Item("“Looking for your D11…” or exit code 3",
                 "The printer is off, asleep or out of range, or the NIIMBOT phone app is connected to it. Close the phone app or turn off the phone's Bluetooth, then turn the printer on.")
            Item("The printer's light turns red and printing stops",
                 "The printer found a problem, usually labels not seated (it can't find the next label) or the lid not fully closed. LabelBridge shows the printer's reason. Open the lid, reseat the roll, close it firmly, and turn the printer off and on if the light stays red.")
            Item("“Bluetooth access needed”",
                 "Allow LabelBridge in System Settings › Privacy & Security › Bluetooth.")
            Item("The print is too light", "Raise the darkness in the window, or use `--density 4`.")
            Item("Text is shortened with “…”", "The label is too long for the space. Use fewer words, or split it into two lines with `\\n`.")
            Item("`labelbridge: command not found`",
                 "Choose LabelBridge › Settings › Repair Setup, or run the command by its full path: `/Applications/LabelBridge.app/Contents/Helpers/labelbridge`.")
            Item("Something else", "Help › Open Log shows what LabelBridge did. The log is at `~/Library/Logs/LabelBridge.log`.")
        }
    }
}

// MARK: - Building blocks

private struct P: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(.init(text)).font(.body).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Steps: View {
    let items: [String]
    init(_ items: [String]) { self.items = items }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(Circle().fill(Color.secondary.opacity(0.15)))
                    Text(.init(item)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct Item: View {
    let title: String, text: String
    init(_ title: String, _ text: String) { self.title = title; self.text = text }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(.init(title)).font(.headline)
            Text(.init(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }
}

private struct Code: View {
    let text: String
    @State private var copied = false
    init(_ text: String) { self.text = text }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // No inner scroll view: it would swallow the page's vertical scrolling.
            Text(text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).padding(.trailing, 64)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }
            .controlSize(.small).padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

/// The built-in help of the bundled `labelbridge` command, so the Help window always matches it.
enum CLIHelp {
    static let text: String = {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/labelbridge")
        let parts = [["--help"], ["help", "print"], ["help", "preview"], ["help", "sticker"], ["help", "sticker", "print"],
                     ["help", "sticker", "export"]].map { run(helper, $0) }
        let joined = parts.compactMap { $0 }.joined(separator: "\n\n────────────────────────────────────────\n\n")
        return joined.isEmpty ? "Run `labelbridge --help` in Terminal." : joined
    }()

    private static func run(_ tool: URL, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        p.environment = ["COLUMNS": "66"]   // fits the help page without wrapping
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
