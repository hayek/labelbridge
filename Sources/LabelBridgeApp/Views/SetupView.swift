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

            VStack(spacing: 0) {
                step("folder.fill", .blue, "Move to Applications",
                     "Keeps the printer and the command working.", flow.applications)
                Divider().padding(.leading, 52)
                step("antenna.radiowaves.left.and.right", .indigo, "Allow Bluetooth",
                     "Lets LabelBridge talk to your D11.", flow.bluetooth)
                Divider().padding(.leading, 52)
                step("printer.fill", .gray, "Add the printer",
                     "Shows up in every app's Print dialog.", flow.printerQueue)
                Divider().padding(.leading, 52)
                step("terminal.fill", .black, "Install the labelbridge command",
                     "Print from Terminal, scripts and AI assistants.", flow.cli)
                Divider().padding(.leading, 52)
                step("power", .orange, "Open at login",
                     "Runs in the background so printing just works.", flow.login)
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))

            Text(footer)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 14)

            HStack {
                Spacer()
                if flow.finished {
                    Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { onClose() }.disabled(flow.running)
                    Button(flow.running ? "Setting Up…" : "Set Up") { Task { await flow.runAll() } }
                        .keyboardShortcut(.defaultAction).disabled(flow.running)
                }
            }
            .controlSize(.large)
            .padding(.top, 14)
        }
        .padding(24)
        .frame(width: 460)
    }

    private var footer: String {
        flow.finished
            ? "All set. Turn the D11 on, and keep the NIIMBOT phone app disconnected while printing from the Mac."
            : "You may be asked for your password to add the printer and the command."
    }

    @ViewBuilder
    private func step(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, _ status: StepStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(tint.gradient))
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
            Spacer(minLength: 8)
            statusMark(status).frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func statusMark(_ status: StepStatus) -> some View {
        switch status {
        case .pending: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.orange)
        case .skipped: Image(systemName: "minus.circle.fill").font(.title3).foregroundStyle(.tertiary)
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
