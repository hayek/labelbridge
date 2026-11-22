import AppKit
import LabelCore

/// Checks GitHub releases for a newer LabelBridge: from the menu, and at most once a day when enabled.
@MainActor
enum Updater {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    private static var checking = false

    /// Runs the daily background check when it's due (called when the app becomes active).
    static func checkIfDue() {
        guard Settings.checkForUpdates,
              Date().timeIntervalSince(Settings.lastUpdateCheck ?? .distantPast) > 24 * 60 * 60 else { return }
        Task { await check(userInitiated: false) }
    }

    /// `userInitiated` shows every outcome; the background check only speaks up when there's an update.
    static func check(userInitiated: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var request = URLRequest(url: UpdateCheck.latestReleaseURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LabelBridge/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            Settings.lastUpdateCheck = Date()
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                if userInitiated { upToDate() }
                return
            }
            let release = try UpdateCheck.parseLatest(data)
            Log.write("update check: latest \(release.version), running \(currentVersion)")
            if UpdateCheck.isNewer(release.version, than: currentVersion) {
                if !userInitiated, Settings.skippedVersion == release.version { return }
                offer(release, userInitiated: userInitiated)
            } else if userInitiated {
                upToDate()
            }
        } catch {
            Log.write("update check failed: \(error)")
            if userInitiated {
                alert("Couldn't check for updates", "Check your internet connection and try again.\n\(error.localizedDescription)")
            }
        }
    }

    private static func offer(_ release: UpdateCheck.Release, userInitiated: Bool) {
        let a = NSAlert()
        a.messageText = "LabelBridge \(release.version) is available"
        a.informativeText = "You have version \(currentVersion). Download the new version, open it, and drag LabelBridge to Applications to replace this one."
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        if !userInitiated { a.addButton(withTitle: "Skip This Version") }
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.download ?? release.page)
        case .alertThirdButtonReturn: Settings.skippedVersion = release.version
        default: break
        }
    }

    private static func upToDate() {
        alert("You're up to date", "LabelBridge \(currentVersion) is the latest version.")
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
