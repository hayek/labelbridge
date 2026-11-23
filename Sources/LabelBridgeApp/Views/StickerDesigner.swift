import SwiftUI
import LabelCore

struct StickerDesigner: View {
    @StateObject private var store = StickerDesignStore()
    @ObservedObject private var service = PrintService.shared
    @State private var selectedID: UUID?
    @State private var sidebarTab = 0
    @State private var choosingIcon = false
    @State private var savingTemplate = false
    @State private var templateName = ""
    @State private var copies = 1
    /// Shared with the text-batch window so both modes print with the same darkness and media.
    @Binding var density: Int
    @Binding var media: LabelMedia
    @State private var printing = false
    @State private var outcome: (ok: Bool, text: String)?

    private var selected: StickerObject? { store.design.objects.first { $0.id == selectedID } }
    private var addToRight: Bool { store.design.shape == .twoCircles && (selected?.frame.x ?? 0) >= 14 }

    var body: some View {
        VStack(spacing: 0) {
            tools
            Divider()
            HStack(spacing: 0) {
                sidebar.frame(width: 230)
                Divider()
                canvas.frame(minWidth: 400, maxWidth: .infinity)
                Divider()
                inspector.frame(width: 300)
            }
        }
        .disabled(printing)
        .onChange(of: store.design) { design in
            if !design.objects.contains(where: { $0.id == selectedID }) { selectedID = nil }
            outcome = nil
        }
        .sheet(isPresented: $savingTemplate) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Save Template").font(.headline)
                TextField("Template name", text: $templateName).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { savingTemplate = false }.keyboardShortcut(.cancelAction)
                    Button("Save") {
                        if store.saveTemplate(name: templateName) { savingTemplate = false; sidebarTab = 0 }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }

    private var tools: some View {
        HStack(spacing: 12) {
            Button { add(.text("Text")) } label: { Label("Add Text", systemImage: "textformat") }
            Button { choosingIcon = true } label: { Label("Add Icon", systemImage: "face.smiling") }
                .popover(isPresented: $choosingIcon) {
                    StickerIconLibrary { icon in add(.icon(icon)); choosingIcon = false }
                }
            Divider().frame(height: 20)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(!store.canUndo).help("Undo")
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(!store.canRedo).help("Redo")
            Spacer()
            Text("Drag to move · Drag the blue handle to resize").font(.caption).foregroundStyle(.secondary)
            Button { templateName = ""; savingTemplate = true } label: { Label("Save Template", systemImage: "square.and.arrow.down") }
        }
        .padding(12)
    }

    private var sidebar: some View {
        VStack(spacing: 12) {
            Picker("Browse", selection: $sidebarTab) {
                Text("Templates").tag(0)
                Text("Objects").tag(1)
            }
            .pickerStyle(.segmented)
            .padding([.top, .horizontal], 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if sidebarTab == 0 {
                        Text("START WITH A TEMPLATE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(StickerTemplate.builtIn) { template in templateCard(template) }
                        if !store.savedTemplates.isEmpty {
                            Text("MY TEMPLATES").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                            ForEach(store.savedTemplates) { template in templateCard(template) }
                        }
                    } else {
                        if store.design.objects.isEmpty {
                            Text("Use Add Text or Add Icon to start your design.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(store.design.objects.enumerated()), id: \.element.id) { index, object in
                            Button { selectedID = object.id } label: {
                                HStack {
                                    Image(systemName: objectSymbol(object)).frame(width: 24)
                                    Text(object.title).lineLimit(2)
                                    Spacer()
                                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedID == object.id ? Color.accentColor.opacity(0.16) : Color.clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func templateCard(_ template: StickerTemplate) -> some View {
        Button {
            store.change { $0 = template.design }
            selectedID = nil
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                let result = Result { try StickerDesignRenderer.render(template.design) }
                if case .success(let rendered) = result {
                    StickerArtwork(design: template.design, bitmap: rendered.bitmap)
                        .frame(height: 88)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color(nsColor: .underPageBackgroundColor))
                } else if case .failure(let error) = result {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .frame(height: 108)
                }
                Text(template.name).font(.callout.weight(.medium))
                Text("\(template.design.size.description) mm").font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.25)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let ratio = store.design.size.lengthMM / store.design.size.widthMM
            let width = min(max(geometry.size.width - 56, 100), max(geometry.size.height - 180, 100) * ratio, 640)
            let result = Result { try StickerDesignRenderer.render(store.design) }
            VStack(spacing: 16) {
                Spacer()
                if case .success(let rendered) = result {
                    StickerCanvas(design: store.design, bitmap: rendered.bitmap, selectedID: $selectedID,
                                  onUpdate: store.update, onBegin: store.beginGesture, onEnd: store.endGesture)
                        .frame(width: width, height: width / ratio)
                    Text(store.design.shape == .twoCircles ? "Two 14 mm circles · 28 × 14 mm per pair" : "\(store.design.size.description) mm")
                        .font(.caption).foregroundStyle(.secondary)
                    if let warning = rendered.warning {
                        ScrollView {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxHeight: 90)
                        .padding(.horizontal, 20)
                    }
                } else if case .failure(let error) = result {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding()
                }
                Spacer()
                Text("Outlines and blue selection handles do not print. Your draft is saved automatically.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(16)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            Form {
                Section("Paper") {
                    if store.design.shape == .twoCircles {
                        LabeledContent("Template", value: "Two 14 mm circles")
                    } else {
                        Picker("Size", selection: Binding(get: { store.design.size }, set: { size in
                            store.change { design in
                                design.size = size
                                for index in design.objects.indices { design.objects[index].frame = design.objects[index].frame.clamped(to: size) }
                            }
                        })) {
                            ForEach(LabelSize.builtIn + (LabelSize.builtIn.contains(store.design.size) ? [] : [store.design.size]), id: \.self) {
                                Text("\($0.description) mm").tag($0)
                            }
                        }
                    }
                    Picker("Media", selection: $media) {
                        ForEach(LabelMedia.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: media) { Settings.media = $0 }
                }
                if let selected {
                    StickerObjectInspector(object: selected, size: store.design.size, onChange: store.update) {
                        store.change { $0.objects.removeAll { $0.id == selected.id } }
                        selectedID = nil
                    }
                } else {
                    Section("Edit objects") {
                        Text("Click an object on the sticker or in the Objects list to edit its text, icon, position and size.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Print") {
                    Stepper("Copies: \(copies)", value: $copies, in: 1...99)
                    Stepper("Darkness: \(density)", value: $density, in: 1...5)
                        .onChange(of: density) { Settings.density = $0 }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            VStack(spacing: 10) {
                if let error = store.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                if printing, let progress = service.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                }
                Button { Task { await printDesign() } } label: {
                    Text(printing ? "Printing…" : "Print \(copies) \(store.design.shape == .twoCircles ? (copies == 1 ? "Pair" : "Pairs") : (copies == 1 ? "Label" : "Labels"))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("p")
                .disabled(!store.design.objects.contains(where: \.hasContent))
                if let outcome {
                    Text(outcome.text).font(.callout).foregroundStyle(outcome.ok ? Color.secondary : Color.orange)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func objectSymbol(_ object: StickerObject) -> String {
        if case .icon(let icon) = object.content { return icon.rawValue }
        return "textformat"
    }

    private func add(_ content: StickerContent) {
        selectedID = store.add(content, inRightCircle: addToRight)
        sidebarTab = 1
    }

    private func printDesign() async {
        printing = true
        outcome = nil
        defer { printing = false }
        do {
            let rendered = try StickerDesignRenderer.render(store.design)
            let result = await service.print(bitmaps: [rendered.bitmap], settings: PrintSettings(density: density, copies: copies, media: media))
            if result.ok {
                let unit = store.design.shape == .twoCircles ? (result.printed == 1 ? "pair" : "pairs") : (result.printed == 1 ? "label" : "labels")
                outcome = (true, "Printed \(result.printed) \(unit)." + (rendered.warning.map { " " + $0 } ?? ""))
            } else {
                outcome = (false, result.error ?? "Printing failed.")
            }
        } catch {
            Log.write("sticker design: \(error.localizedDescription)")
            outcome = (false, error.localizedDescription)
        }
    }
}
