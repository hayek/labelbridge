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
        Log.write("LabelBridge started")
        AppServices.start()
    }

    /// Closing the window keeps the app running for CLI and Print-dialog jobs.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Background services started with the app (IPC server in Task 7, CUPS listener in Task 8, setup in Task 9).
enum AppServices {
    static func start() { IPCService.start(); CUPSListener.start() }
}

/// Placeholders replaced in Task 9.
enum LoginItem { static func apply(_ on: Bool) {} }
@MainActor final class SetupCoordinator {
    static let shared = SetupCoordinator()
    func present(repair: Bool) {}
    func confirmUninstall() {}
}
