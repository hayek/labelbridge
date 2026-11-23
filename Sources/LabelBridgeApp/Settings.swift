import Foundation
import LabelCore

enum LabelLayout: String, CaseIterable {
    case text, designer

    var title: String { self == .text ? "Text batch" : "Sticker designer" }
}

/// User defaults shared by the window, the CLI service and the Print-dialog listener.
enum Settings {
    private static let d = UserDefaults.standard
    static var labelSize: LabelSize {
        get { d.string(forKey: "labelSize").flatMap(LabelSize.init(parsing:)) ?? .defaultSize }
        set { d.set(newValue.description, forKey: "labelSize") }
    }
    static var density: Int {
        get { d.object(forKey: "density") as? Int ?? 3 }
        set { d.set(newValue, forKey: "density") }
    }
    static var media: LabelMedia {
        get { d.string(forKey: "media").flatMap(LabelMedia.init(rawValue:)) ?? .gaps }
        set { d.set(newValue.rawValue, forKey: "media") }
    }
    /// Where sticker ink lands relative to the design (mm), set from an alignment test print.
    static var stickerOffset: StickerOffset {
        get { StickerOffset(x: d.double(forKey: "stickerOffsetX"), y: d.double(forKey: "stickerOffsetY")) }
        set { d.set(newValue.x, forKey: "stickerOffsetX"); d.set(newValue.y, forKey: "stickerOffsetY") }
    }
    static var layout: LabelLayout {
        get { d.string(forKey: "layout").flatMap(LabelLayout.init(rawValue:)) ?? .text }
        set { d.set(newValue.rawValue, forKey: "layout") }
    }
    static var fontName: String? {
        get { d.string(forKey: "fontName") }
        set { d.set(newValue, forKey: "fontName") }
    }
    static var bold: Bool {
        get { d.bool(forKey: "bold") }
        set { d.set(newValue, forKey: "bold") }
    }
    static var alignment: Alignment {
        get { d.string(forKey: "alignment").flatMap(Alignment.init(rawValue:)) ?? .center }
        set { d.set(newValue.rawValue, forKey: "alignment") }
    }
    static var openAtLogin: Bool {
        get { d.object(forKey: "openAtLogin") as? Bool ?? false }
        set { d.set(newValue, forKey: "openAtLogin") }
    }
    static var checkForUpdates: Bool {
        get { d.object(forKey: "checkForUpdates") as? Bool ?? true }
        set { d.set(newValue, forKey: "checkForUpdates") }
    }
    static var lastUpdateCheck: Date? {
        get { d.object(forKey: "lastUpdateCheck") as? Date }
        set { d.set(newValue, forKey: "lastUpdateCheck") }
    }
    static var skippedVersion: String? {
        get { d.string(forKey: "skippedVersion") }
        set { d.set(newValue, forKey: "skippedVersion") }
    }
    static var style: TextStyle { TextStyle(fontName: fontName, bold: bold, alignment: alignment) }
}
