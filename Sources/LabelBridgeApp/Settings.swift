import Foundation
import LabelCore

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
