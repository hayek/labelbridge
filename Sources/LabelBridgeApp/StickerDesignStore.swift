import SwiftUI
import LabelCore

@MainActor
final class StickerDesignStore: ObservableObject {
    @Published private(set) var design: StickerDesign {
        didSet { persistDesign() }
    }
    @Published private(set) var savedTemplates: [StickerTemplate]
    @Published var error: String?
    @Published private var past: [StickerDesign] = []
    @Published private var future: [StickerDesign] = []
    private var gestureStart: StickerDesign?
    private let defaults: UserDefaults

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var design = StickerTemplate.builtIn[0].design
        var templates: [StickerTemplate] = []
        var errors: [String] = []
        if let data = defaults.data(forKey: StickerLibrary.draftKey) {
            do {
                let saved = try JSONDecoder().decode(StickerDesign.self, from: data)
                try saved.validate()
                design = saved
            } catch {
                errors.append("Couldn't restore your design: \(error.localizedDescription)")
            }
        }
        if let data = defaults.data(forKey: StickerLibrary.templatesKey) {
            do {
                templates = try JSONDecoder().decode([StickerTemplate].self, from: data)
                for template in templates { try template.design.validate() }
            } catch {
                templates = []
                errors.append("Couldn't load saved templates: \(error.localizedDescription)")
            }
        }
        self.design = design
        savedTemplates = templates
        // Save the starting design so `labelbridge sticker print draft` works before the first edit.
        if defaults.data(forKey: StickerLibrary.draftKey) == nil { persistDesign() }
        self.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
        for message in errors { Log.write(message) }
    }

    func change(_ update: (inout StickerDesign) -> Void) {
        var next = design
        update(&next)
        guard next != design else { return }
        do {
            try next.validate()
            if gestureStart == nil { remember(design) }
            design = next
        } catch { report(error) }
    }

    func update(_ object: StickerObject) {
        change { design in
            guard let index = design.objects.firstIndex(where: { $0.id == object.id }) else { return }
            var next = object
            next.frame = next.frame.clamped(to: design.size)
            design.objects[index] = next
        }
    }

    func add(_ content: StickerContent, inRightCircle: Bool) -> UUID? {
        guard design.objects.count < 100 else {
            report(StickerDesignError.invalidGeometry)
            return nil
        }
        let width = min(8, design.size.lengthMM - 2)
        let height: Double
        if case .text = content { height = min(3, design.size.widthMM - 2) } else { height = min(8, design.size.widthMM - 2) }
        let center = design.shape == .twoCircles ? (inRightCircle ? 21.0 : 7.0) : design.size.lengthMM / 2
        let object = StickerObject(content: content,
                                   frame: .init(x: center - width / 2, y: (design.size.widthMM - height) / 2,
                                                width: width, height: height))
        change { $0.objects.append(object) }
        return object.id
    }

    func beginGesture() { if gestureStart == nil { gestureStart = design } }

    func endGesture() {
        if let start = gestureStart, start != design { remember(start) }
        gestureStart = nil
    }

    func undo() {
        guard let previous = past.popLast() else { return }
        future.append(design)
        design = previous
    }

    func redo() {
        guard let next = future.popLast() else { return }
        past.append(design)
        design = next
    }

    func saveTemplate(name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            let updated = savedTemplates + [StickerTemplate(name: name, design: design)]
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: StickerLibrary.templatesKey)
            savedTemplates = updated
            return true
        } catch { report(error); return false }
    }

    private func remember(_ design: StickerDesign) {
        past.append(design)
        if past.count > 50 { past.removeFirst(past.count - 50) }
        future = []
    }

    private func persistDesign() {
        do { defaults.set(try JSONEncoder().encode(design), forKey: StickerLibrary.draftKey) }
        catch { report(error) }
    }

    private func report(_ error: Error) {
        let message = "Sticker designer: \(error.localizedDescription)"
        Log.write(message)
        self.error = message
    }
}
