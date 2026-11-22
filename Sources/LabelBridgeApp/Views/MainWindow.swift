import SwiftUI
import LabelCore

/// Main window: labels on the left, a live preview in the middle, options and Print on the right.
struct MainWindow: View {
    @ObservedObject var service = PrintService.shared
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""
    @State private var size = Settings.labelSize
    @State private var density = Settings.density
    @State private var copies = 1
    @State private var alignment = Settings.alignment
    @State private var fontName = Settings.fontName ?? ""
    @State private var bold = Settings.bold
    @State private var printing = false
    @State private var outcome: (ok: Bool, text: String)?

    private static let previewLimit = 100
    private static let fontFamilies = NSFontManager.shared.availableFontFamilies

    private var parsed: (items: [String], skipped: Int) { Batch.items(from: text) }
    private var style: TextStyle { TextStyle(fontName: fontName.isEmpty ? nil : fontName, bold: bold, alignment: alignment) }
    private var labelCount: Int { parsed.items.count * copies }

    var body: some View {
        HStack(spacing: 0) {
            editor.frame(width: 260)
            Divider()
            canvas.frame(minWidth: 380, maxWidth: .infinity)
            Divider()
            inspector.frame(width: 300)
        }
        .frame(minWidth: 960, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .status) { ToolbarPrinterStatus() }
        }
        .onAppear { MainWindowOpener.open = { [openWindow] in openWindow(id: "main") } }
    }

    // MARK: - Labels

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Labels").font(.headline)
                Spacer()
                if !parsed.items.isEmpty {
                    Text("\(parsed.items.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11)
                if text.isEmpty {
                    Text("Type or paste names,\none per line")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                }
            }

            Divider()
            Text("One label per line. Type \\n for a line break." + (parsed.skipped > 0 ? " \(parsed.skipped) blank lines skipped." : ""))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Preview

    private var canvas: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if parsed.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag").font(.system(size: 38, weight: .light))
                    Text("Your labels will appear here").font(.title3)
                    Text("Any language works, including Hebrew and Arabic.").font(.callout)
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(Array(parsed.items.prefix(Self.previewLimit).enumerated()), id: \.offset) { _, item in
                            LabelPreview(text: item, size: size, style: style)
                                .frame(width: 340)
                                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        }
                        if parsed.items.count > Self.previewLimit {
                            Text("+ \(parsed.items.count - Self.previewLimit) more").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Options and Print

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                Section("Label") {
                    Picker("Size", selection: $size) {
                        ForEach(LabelSize.builtIn + (LabelSize.builtIn.contains(size) ? [] : [size]), id: \.self) {
                            Text("\($0.widthMM.formatted()) × \($0.lengthMM.formatted()) mm")
                        }
                    }
                    .onChange(of: size) { Settings.labelSize = $0 }
                    LabeledContent("Copies") {
                        Stepper("\(copies)", value: $copies, in: 1...99).monospacedDigit()
                    }
                    LabeledContent("Darkness") {
                        Slider(value: Binding(get: { Double(density) },
                                              set: { density = Int($0.rounded()); Settings.density = density }),
                               in: 1...5, step: 1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "sun.min").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Text") {
                    Picker("Font", selection: $fontName) {
                        Text("System").tag("")
                        Divider()
                        ForEach(Self.fontFamilies, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: fontName) { Settings.fontName = $0.isEmpty ? nil : $0 }
                    Toggle("Bold", isOn: $bold)
                        .onChange(of: bold) { Settings.bold = $0 }
                    Picker("Alignment", selection: $alignment) {
                        Image(systemName: "text.alignleft").help("Start of the line").tag(Alignment.leading)
                        Image(systemName: "text.aligncenter").help("Center").tag(Alignment.center)
                        Image(systemName: "text.alignright").help("End of the line").tag(Alignment.trailing)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: alignment) { Settings.alignment = $0 }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            VStack(spacing: 10) {
                if printing, let p = service.progress {
                    ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                }
                Button { Task { await print() } } label: {
                    Text(printButtonTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("p")
                .disabled(printing || parsed.items.isEmpty)

                if let outcome {
                    Label(outcome.text, systemImage: outcome.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(outcome.ok ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var printButtonTitle: String {
        if printing { return "Printing…" }
        switch labelCount {
        case 0: return "Print"
        case 1: return "Print 1 Label"
        default: return "Print \(labelCount) Labels"
        }
    }

    private func print() async {
        printing = true
        outcome = nil
        let job = LabelJob(items: Batch.lines(from: text), size: size, style: style,
                           settings: PrintSettings(density: density, copies: copies), source: .window)
        let r = await service.print(job)
        printing = false
        if r.ok {
            let shortened = r.warnings.isEmpty ? "" : " (\(r.warnings.count) shortened to fit)"
            outcome = (true, "Printed \(r.printed) \(r.printed == 1 ? "label" : "labels")" + shortened)
        } else {
            outcome = (false, r.error ?? "Printing failed")
        }
    }
}

/// Compact printer status for the toolbar; click for details.
struct ToolbarPrinterStatus: View {
    @ObservedObject var service = PrintService.shared
    @State private var showDetails = false

    var body: some View {
        let status = service.printerStatus
        Button { showDetails.toggle() } label: {
            HStack(spacing: 6) {
                switch status.kind {
                case .ready: Circle().fill(.green).frame(width: 8, height: 8)
                case .problem: Circle().fill(.orange).frame(width: 8, height: 8)
                case .searching, .busy: ProgressView().controlSize(.mini)
                }
                Text(status.title).font(.callout)
            }
            .padding(.horizontal, 6)
        }
        .help(status.detail)
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            PrinterStatusView().padding(16).frame(width: 340)
        }
    }
}
