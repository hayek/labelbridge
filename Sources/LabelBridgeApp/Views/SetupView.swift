import SwiftUI
import LabelCore

struct SetupView: View {
    @ObservedObject var flow: SetupFlow
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 72, height: 72)
                Text("Welcome to LabelBridge").font(.title2.weight(.semibold))
                Text("Print labels to your NIIMBOT D11 over Bluetooth.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 14) {
                Text(flow.finished ? "Setup finished:" : "Clicking Start Setup will:")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 0) {
                    step(1, "Move LabelBridge to Applications",
                         "Keeps the printer and the command working.", flow.applications)
                    step(2, "Ask for Bluetooth access",
                         "So LabelBridge can talk to your D11.", flow.bluetooth)
                    step(3, "Add the printer “NIIMBOT D11”",
                         "So it shows up in every app's Print dialog.", flow.printerQueue)
                    step(4, "Install the labelbridge command",
                         "So Terminal, scripts and AI assistants can print.", flow.cli)
                    step(5, "Open LabelBridge at login",
                         "Runs in the background so printing just works.", flow.login, last: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(footer)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)

            HStack {
                Spacer()
                if flow.finished {
                    Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { onClose() }.disabled(flow.running)
                    Button(flow.running ? "Setting Up…" : "Start Setup") { Task { await flow.runAll() } }
                        .keyboardShortcut(.defaultAction).disabled(flow.running)
                }
            }
            .controlSize(.large)
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 460)
    }

    private var footer: String {
        flow.finished
            ? "All set. Turn the D11 on, and keep the NIIMBOT phone app disconnected while printing from the Mac."
            : "It takes a few seconds. macOS may ask for your password."
    }

    @ViewBuilder
    private func step(_ number: Int, _ title: String, _ detail: String, _ status: StepStatus, last: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                marker(number, status).frame(width: 24, height: 24)
                if !last {
                    Rectangle().fill(.separator).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Group {
                    switch status {
                    case .failed(let message): Text(message).foregroundStyle(.orange)
                    case .skipped(let message): Text(message).textSelection(.enabled)
                    default: Text(detail)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
            .padding(.bottom, last ? 0 : 14)
        }
    }

    @ViewBuilder
    private func marker(_ number: Int, _ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Text("\(number)").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.circle.fill").font(.title2).foregroundStyle(.orange)
        case .skipped: Image(systemName: "minus.circle.fill").font(.title2).foregroundStyle(.secondary)
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
