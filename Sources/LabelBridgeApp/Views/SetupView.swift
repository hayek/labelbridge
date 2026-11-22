import SwiftUI
import LabelCore

struct SetupView: View {
    @ObservedObject var flow: SetupFlow
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up LabelBridge").font(.title2.bold())
            Text("Print to your NIIMBOT D11 over Bluetooth from this window, the labelbridge command and any app's Print dialog.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                row("Applications folder", flow.applications)
                row("Bluetooth access", flow.bluetooth)
                row("Printer “NIIMBOT D11 (Bluetooth)”", flow.printerQueue)
                row("labelbridge command", flow.cli)
                row("Open at login", flow.login)
                row("Test label", flow.testLabel)
            }
            Text("Turn the D11 on and disconnect the NIIMBOT phone app before printing.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Print Test Label") { Task { await flow.printTestLabel() } }.disabled(flow.running)
                Spacer()
                Button("Done") { onClose() }
                Button("Set Up") { Task { await flow.runAll() } }.keyboardShortcut(.defaultAction).disabled(flow.running)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder private func row(_ title: String, _ status: StepStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch status {
            case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
            case .running: ProgressView().controlSize(.small)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if case .failed(let m) = status { Text(m).font(.caption).foregroundStyle(.orange) }
                if case .skipped(let m) = status { Text(m).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            }
        }
    }
}

/// Shows the setup window and handles uninstall.
@MainActor
final class SetupCoordinator {
    static let shared = SetupCoordinator()
    private var window: NSWindow?
    private let flow = SetupFlow()

    func present(repair: Bool) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "LabelBridge Setup"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SetupView(flow: flow) { [weak self] in self?.window?.close() })
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall LabelBridge?"
        alert.informativeText = "This removes the “NIIMBOT D11 (Bluetooth)” printer, the labelbridge command and the login item, then moves the app to the Trash."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        SetupFlow.uninstall()
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in DispatchQueue.main.async { NSApp.terminate(nil) } }
    }
}
