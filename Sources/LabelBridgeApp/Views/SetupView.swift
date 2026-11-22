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
            .padding(.bottom, 22)

            PrinterStatusView()
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))

            VStack(alignment: .leading, spacing: 8) {
                if flow.running || flow.finished {
                    ProgressView(value: progress).progressViewStyle(.linear)
                        .tint(problems.isEmpty ? .accentColor : .orange)
                }
                Text(progressText)
                    .font(.callout)
                    .foregroundStyle(flow.finished && !problems.isEmpty ? .orange : .secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 56, alignment: .top)
            .padding(.top, 20)

            HStack {
                Spacer()
                if flow.finished {
                    Button("Done") { onClose() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now") { onClose() }.disabled(flow.running)
                    Button("Start Setup") { Task { await flow.runAll() } }
                        .keyboardShortcut(.defaultAction).disabled(flow.running)
                }
            }
            .controlSize(.large)
            .padding(.top, 12)
        }
        .padding(24)
        .frame(width: 440)
        .animation(.default, value: progress)
    }

    private var steps: [(text: String, status: StepStatus)] {
        [("Moving LabelBridge to Applications…", flow.applications),
         ("Asking for Bluetooth access…", flow.bluetooth),
         ("Adding the printer to macOS…", flow.printerQueue),
         ("Installing the labelbridge command…", flow.cli)]
    }

    private var progress: Double {
        let finished = steps.filter { $0.status != .pending && $0.status != .running }.count
        return Double(finished) / Double(steps.count)
    }

    private var problems: [String] {
        steps.compactMap {
            if case .failed(let m) = $0.status { return m }
            if case .skipped(let m) = $0.status, $0.text.contains("command") { return "The labelbridge command wasn't installed. \(m)" }
            return nil
        }
    }

    private var progressText: String {
        if flow.finished {
            return problems.isEmpty
                ? "All set. Print from this app, from any app's Print dialog, or with the labelbridge command."
                : problems.joined(separator: "\n")
        }
        if flow.running {
            return (steps.first { $0.status == .running } ?? steps.first { $0.status == .pending })?.text ?? "Finishing…"
        }
        return "Setup adds the printer to macOS and installs the labelbridge command. macOS may ask for your password."
    }
}

/// Shows the setup window and handles uninstall.
@MainActor
final class SetupCoordinator {
    static let shared = SetupCoordinator()
    private var window: NSWindow?
    private var flow = SetupFlow()

    /// Shows the setup window. Unless setup is running, it starts fresh (so Repair can run again).
    func present(repair: Bool) {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "LabelBridge Setup"
            w.isReleasedWhenClosed = false
            window = w
        }
        if !flow.running || window?.contentView == nil {
            if !flow.running { flow = SetupFlow() }
            window?.contentView = NSHostingView(rootView: SetupView(flow: flow) { [weak self] in self?.window?.close() })
            window?.center()
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
