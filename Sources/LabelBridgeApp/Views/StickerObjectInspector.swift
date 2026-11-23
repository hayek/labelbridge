import SwiftUI
import LabelCore

struct StickerIconLibrary: View {
    let onPick: (StickerIcon) -> Void
    @State private var search = ""

    private static let available = StickerIcon.allCases.filter {
        NSImage(systemSymbolName: $0.rawValue, accessibilityDescription: nil) != nil
    }

    private var filtered: [StickerIcon] {
        Self.available.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an icon").font(.headline)
            TextField("Search icons", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                if filtered.isEmpty { Text("No matching icons.").foregroundStyle(.secondary).padding() }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                    ForEach(filtered, id: \.self) { icon in
                        Button { onPick(icon) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: icon.rawValue).font(.system(size: 24)).frame(height: 32)
                                Text(icon.title).font(.caption).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 66)
                            .padding(4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(icon.title)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320, height: 360)
    }
}

struct StickerObjectInspector: View {
    let object: StickerObject
    let size: LabelSize
    let onChange: (StickerObject) -> Void
    let onDelete: () -> Void
    @State private var choosingIcon = false
    @FocusState private var editingText: Bool
    private static let fonts = NSFontManager.shared.availableFontFamilies

    var body: some View {
        Section("Selected object") {
            switch object.content {
            case .text(let text):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text content").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { text }, set: {
                        var next = object; next.content = .text($0); onChange(next)
                    }))
                    .font(.system(size: 14))
                    .focused($editingText)
                    .frame(height: 80)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.35)))
                    .accessibilityLabel("Text content")
                    Text("Changes appear on the sticker immediately.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Font", selection: Binding(get: { object.style.fontName ?? "" }, set: {
                    var next = object; next.style.fontName = $0.isEmpty ? nil : $0; onChange(next)
                })) {
                    Text("System").tag("")
                    ForEach(Self.fonts, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Bold", isOn: binding(\.style.bold))
                Toggle("Italic", isOn: binding(\.style.italic))
                Toggle("Auto-fit text", isOn: Binding(get: { object.style.fontSizePoints == nil }, set: {
                    var next = object; next.style.fontSizePoints = $0 ? nil : 8; onChange(next)
                }))
                if let points = object.style.fontSizePoints {
                    let value = Binding(get: { points }, set: {
                        var next = object
                        next.style.fontSizePoints = min(max($0, TextStyle.fontSizeRange.lowerBound), TextStyle.fontSizeRange.upperBound)
                        onChange(next)
                    })
                    LabeledContent("Font size") {
                        TextField("Font size", value: value, format: .number.precision(.fractionLength(0...1)))
                            .labelsHidden().multilineTextAlignment(.trailing).frame(width: 48)
                        Text("pt").foregroundStyle(.secondary)
                        Stepper("Font size", value: value, in: TextStyle.fontSizeRange, step: 0.5).labelsHidden()
                    }
                } else {
                    Text("Resize the object to change its fitted text size.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Alignment", selection: binding(\.style.alignment)) {
                    Image(systemName: "text.alignleft").tag(Alignment.leading)
                    Image(systemName: "text.aligncenter").tag(Alignment.center)
                    Image(systemName: "text.alignright").tag(Alignment.trailing)
                }
                .pickerStyle(.segmented)
            case .icon(let icon):
                Button { choosingIcon = true } label: { Label(icon.title, systemImage: icon.rawValue) }
                    .popover(isPresented: $choosingIcon) {
                        StickerIconLibrary { icon in
                            var next = object; next.content = .icon(icon); onChange(next); choosingIcon = false
                        }
                    }
            }
            dimension("X", path: \.frame.x, range: 0...max(0, size.lengthMM - object.frame.width))
            dimension("Y", path: \.frame.y, range: 0...max(0, size.widthMM - object.frame.height))
            dimension("Width", path: \.frame.width, range: 1...max(1, size.lengthMM - object.frame.x))
            dimension("Height", path: \.frame.height, range: 1...max(1, size.widthMM - object.frame.y))
            Button(role: .destructive, action: onDelete) { Label("Delete object", systemImage: "trash") }
        }
        .onAppear { focusText() }
        .onChange(of: object.id) { _ in focusText() }
    }

    private func focusText() {
        if case .text = object.content { editingText = true } else { editingText = false }
    }

    private func binding<Value>(_ path: WritableKeyPath<StickerObject, Value>) -> Binding<Value> {
        Binding(get: { object[keyPath: path] }, set: {
            var next = object; next[keyPath: path] = $0; onChange(next)
        })
    }

    private func dimension(_ title: String, path: WritableKeyPath<StickerObject, Double>,
                           range: ClosedRange<Double>) -> some View {
        let value = Binding(get: { object[keyPath: path] }, set: {
            var next = object
            next[keyPath: path] = min(max($0, range.lowerBound), range.upperBound)
            onChange(next)
        })
        return LabeledContent(title) {
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Text("mm").foregroundStyle(.secondary)
            Stepper(title, value: value, in: range, step: 0.25).labelsHidden()
        }
    }
}
