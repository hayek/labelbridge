import AppKit
import CoreBluetooth
import ServiceManagement
import LabelCore

enum StepStatus: Equatable { case pending, running, done, failed(String), skipped(String) }

/// First-launch setup: Applications folder, Bluetooth, printer queue, CLI, login item.
@MainActor
final class SetupFlow: ObservableObject {
    @Published var applications: StepStatus = .pending
    @Published var bluetooth: StepStatus = .pending
    @Published var printerQueue: StepStatus = .pending
    @Published var cli: StepStatus = .pending
    @Published var login: StepStatus = .pending
    @Published var running = false
    @Published var finished = false

    static let setupVersion = 1
    static var completed: Bool { UserDefaults.standard.integer(forKey: "setupVersion") >= setupVersion }

    static func needsSetup() -> Bool {
        !completed || !queueInstalled() || !cliInstalled()
    }

    static func queueInstalled() -> Bool { run("/usr/bin/lpstat", ["-p", SetupCommands.queueName]).status == 0 }
    static func cliInstalled() -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: SetupCommands.cliLink)) == helperPath
    }
    static var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/labelbridge").path }
    static var ppdPath: String? { Bundle.main.path(forResource: "NIIMBOT_D11", ofType: "ppd") }

    func runAll() async {
        running = true
        defer { running = false }
        guard moveToApplicationsIfNeeded() else { return }   // relaunches from /Applications
        await requestBluetooth()
        installQueue()
        installCLI()
        applyLogin()
        if case .failed = printerQueue {} else { UserDefaults.standard.set(Self.setupVersion, forKey: "setupVersion") }
        finished = true
    }

    /// Returns false when the app is relaunching from /Applications.
    private func moveToApplicationsIfNeeded() -> Bool {
        let path = Bundle.main.bundlePath
        if SetupCommands.isInApplications(path) { applications = .done; return true }
        let alert = NSAlert()
        alert.messageText = "Move LabelBridge to the Applications folder?"
        alert.informativeText = "The printer and the labelbridge command need a stable location."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { applications = .skipped("Running from \(path)"); return true }
        let target = "/Applications/LabelBridge.app"
        do {
            if FileManager.default.fileExists(atPath: target) { try FileManager.default.trashItem(at: URL(fileURLWithPath: target), resultingItemURL: nil) }
            try FileManager.default.copyItem(atPath: path, toPath: target)
            _ = Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target])
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: .init()) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return false
        } catch {
            applications = .failed(error.localizedDescription)
            return true
        }
    }

    private func requestBluetooth() async {
        bluetooth = .running
        _ = PrintService.shared                    // creates the Bluetooth central, which asks for permission
        for _ in 0..<120 where CBCentralManager.authorization == .notDetermined { try? await Task.sleep(for: .milliseconds(500)) }
        switch CBCentralManager.authorization {
        case .allowedAlways: bluetooth = .done
        default:
            bluetooth = .failed("Allow LabelBridge in System Settings › Privacy & Security › Bluetooth.")
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Bluetooth")!)
        }
    }

    private func installQueue() {
        guard let ppd = Self.ppdPath else { printerQueue = .failed("Printer description missing from the app."); return }
        _ = Self.run("/usr/sbin/lpadmin", ["-x", SetupCommands.queueName])
        let args = SetupCommands.addQueueArguments(ppdPath: ppd)
        if Self.run("/usr/sbin/lpadmin", args).status != 0 || !Self.queueInstalled() {
            let cmd = (["/usr/sbin/lpadmin"] + args).map(SetupCommands.quote).joined(separator: " ")
            _ = Self.runAsAdmin(cmd, prompt: "LabelBridge wants to add the printer “\(SetupCommands.queueDescription)”.")
        }
        printerQueue = Self.queueInstalled() ? .done : .failed("Couldn't add the printer.")
    }

    private func installCLI() {
        if Self.cliInstalled() { cli = .done; return }
        let ok = Self.runAsAdmin(SetupCommands.installCLICommand(helperPath: Self.helperPath),
                                 prompt: "LabelBridge wants to install the labelbridge command in /usr/local/bin.")
        cli = ok && Self.cliInstalled() ? .done : .skipped("Use the full path: \(Self.helperPath)")
    }

    private func applyLogin() {
        LoginItem.apply(Settings.openAtLogin)
        login = Settings.openAtLogin ? (SMAppService.mainApp.status == .enabled ? .done : .failed("Turn on LabelBridge in System Settings › General › Login Items.")) : .skipped("Off in Settings")
    }

    // MARK: - Uninstall

    static func uninstall() {
        _ = run("/usr/sbin/lpadmin", ["-x", SetupCommands.queueName])
        if FileManager.default.fileExists(atPath: SetupCommands.cliLink) || (try? FileManager.default.destinationOfSymbolicLink(atPath: SetupCommands.cliLink)) != nil {
            _ = runAsAdmin(SetupCommands.removeCLICommand(), prompt: "LabelBridge wants to remove the labelbridge command.")
        }
        try? SMAppService.mainApp.unregister()
        UserDefaults.standard.removeObject(forKey: "setupVersion")
        Log.write("uninstalled printer, command and login item")
    }

    // MARK: - Helpers

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    /// Runs a shell command as administrator using the standard macOS password prompt.
    static func runAsAdmin(_ command: String, prompt: String) -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { Log.write("admin command failed: \(error)") }
        return error == nil
    }
}

enum LoginItem {
    static func apply(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item: \(error)")
        }
    }

    /// True when macOS opened the app as a login item.
    static var launchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication &&
            event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}
