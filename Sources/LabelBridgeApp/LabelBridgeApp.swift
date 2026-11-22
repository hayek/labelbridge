import SwiftUI

struct LabelBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("LabelBridge", id: "main") {
            MainWindow()
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Open Log") { NSWorkspace.shared.open(Log.url) }
            }
        }
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

    /// Closing the window keeps the app running for CLI and Print-dialog jobs.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Background services started with the app (IPC server in Task 7, CUPS listener in Task 8, setup in Task 9).
enum AppServices {
    static func start() { IPCService.start(); CUPSListener.start() }
}

