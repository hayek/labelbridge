import SwiftUI

struct LabelBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("LabelBridge", id: "main") {
            MainWindow()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .help) { HelpMenuItems() }
        }
        Window("LabelBridge Help", id: "help") {
            HelpView()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        SwiftUI.Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let atLogin = LoginItem.launchedAtLogin
        Log.write("LabelBridge started\(atLogin ? " (login item)" : "")")
        AppServices.start()
        if atLogin {
            // Opened at login: stay in the background so the CLI and Print dialog work.
            DispatchQueue.main.async { NSApp.windows.forEach { $0.close() }; NSApp.hide(nil) }
        } else if SetupFlow.needsSetup() {
            DispatchQueue.main.async { SetupCoordinator.shared.present(repair: false) }
        }
    }

    /// Clicking the Dock icon (or opening the app again) brings the main window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowOpener.open?() }
        return true
    }

    /// Closing the window keeps the app running for CLI and Print-dialog jobs.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Background services started with the app (IPC server in Task 7, CUPS listener in Task 8, setup in Task 9).
enum AppServices {
    static func start() { IPCService.start(); CUPSListener.start() }
}


/// Lets AppKit code reopen the SwiftUI main window after it was closed.
@MainActor
enum MainWindowOpener {
    static var open: (() -> Void)?
}

/// Help menu: opens the Help window (⌘?) and the log.
struct HelpMenuItems: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("LabelBridge Help") { openWindow(id: "help") }.keyboardShortcut("?", modifiers: .command)
        Divider()
        Button("Open Log") { NSWorkspace.shared.open(Log.url) }
    }
}
