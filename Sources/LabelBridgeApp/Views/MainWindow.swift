import SwiftUI
import LabelCore

struct MainWindow: View {
    @ObservedObject var service = PrintService.shared
    @State private var text = ""
    @State private var size = Settings.labelSize
    @State private var density = Settings.density
    @State private var copies = 1
    @State private var alignment = Settings.alignment
    @State private var fontName = Settings.fontName ?? ""
    @State private var bold = Settings.bold
    @State private var printing = false
    @State private var message: String?

    private var parsed: (items: [String], skipped: Int) { Batch.items(from: text) }
    private var style: TextStyle { TextStyle(fontName: fontName.isEmpty ? nil : fontName, bold: bold, alignment: alignment) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(service.statusText).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Labels: one per line").font(.headline)
                    TextEditor(text: $text)
                        .font(.system(size: 15))
                        .frame(minWidth: 280, minHeight: 260)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.3)))
                    Text("\(parsed.items.count) labels" + (parsed.skipped > 0 ? " · \(parsed.skipped) blank lines skipped" : "") + " · type \\n for a line break")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    options
                    Text("Preview").font(.headline)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(parsed.items.prefix(6).enumerated()), id: \.offset) { _, item in
                                LabelPreview(text: item, size: size, style: style).frame(maxWidth: 320)
                            }
                            if parsed.items.count > 6 { Text("+ \(parsed.items.count - 6) more").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(minWidth: 320, minHeight: 160)
                }
            }
            HStack {
                if let message { Text(message).font(.callout).foregroundStyle(service.lastResult?.ok == false ? .red : .secondary) }
                Spacer()
                if let p = service.progress, printing { ProgressView(value: Double(p.done), total: Double(max(p.total, 1))).frame(width: 140) }
                Button(printing ? "Printing…" : "Print \(parsed.items.count * copies) Labels") { Task { await print() } }
                    .keyboardShortcut("p")
                    .disabled(printing || parsed.items.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 460)
    }

    private var options: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                Text("Size")
                Picker("", selection: $size) {
                    ForEach(LabelSize.builtIn + (LabelSize.builtIn.contains(size) ? [] : [size]), id: \.self) { Text("\($0.description) mm") }
                }.labelsHidden().frame(width: 140)
                    .onChange(of: size) { Settings.labelSize = $0 }
            }
            GridRow {
                Text("Darkness")
                Stepper("\(density)", value: $density, in: 1...5).onChange(of: density) { Settings.density = $0 }
            }
            GridRow {
                Text("Copies")
                Stepper("\(copies)", value: $copies, in: 1...99)
            }
            GridRow {
                Text("Align")
                Picker("", selection: $alignment) {
                    Text("Center").tag(Alignment.center); Text("Start").tag(Alignment.leading); Text("End").tag(Alignment.trailing)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    .onChange(of: alignment) { Settings.alignment = $0 }
            }
            GridRow {
                Text("Font")
                HStack {
                    Picker("", selection: $fontName) {
                        Text("System").tag("")
                        ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 160)
                        .onChange(of: fontName) { Settings.fontName = $0.isEmpty ? nil : $0 }
                    Toggle("Bold", isOn: $bold).fixedSize().onChange(of: bold) { Settings.bold = $0 }
                }
            }
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .found, .printing: return .green
        case .searching, .idle: return .gray
        default: return .orange
        }
    }

    private func print() async {
        printing = true
        message = nil
        let job = LabelJob(items: text.components(separatedBy: .newlines), size: size, style: style,
                           settings: PrintSettings(density: density, copies: copies), source: .window)
        let r = await service.print(job)
        printing = false
        message = r.ok ? "Printed \(r.printed) labels" + (r.warnings.isEmpty ? "" : " (\(r.warnings.count) shortened)") : r.error
    }
}
