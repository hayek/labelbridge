import SwiftUI
import LabelCore

/// LabelBridge › Settings (⌘,).
struct SettingsView: View {
    @State private var openAtLogin = Settings.openAtLogin
    @State private var checkForUpdates = Settings.checkForUpdates
    @State private var checking = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $openAtLogin) {
                    Text("Open at login")
                    Text("Starts hidden in the background, so the Print dialog works without opening LabelBridge first.")
                }
                .onChange(of: openAtLogin) { Settings.openAtLogin = $0; LoginItem.apply($0) }
            } footer: {
                Text("Label size, darkness, font and alignment are remembered from the main window, and the labelbridge command uses them as defaults.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Updates") {
                Toggle(isOn: $checkForUpdates) {
                    Text("Check for updates automatically")
                    Text("Once a day, on GitHub.")
                }
                .onChange(of: checkForUpdates) { Settings.checkForUpdates = $0 }
                LabeledContent("Version \(Updater.currentVersion)") {
                    Button(checking ? "Checking…" : "Check Now") {
                        Task { checking = true; await Updater.check(userInitiated: true); checking = false }
                    }
                    .disabled(checking)
                }
            }

            Section("Troubleshooting") {
                LabeledContent {
                    Button("Open Log") { NSWorkspace.shared.open(Log.url) }
                } label: {
                    Text("Log")
                    Text("What LabelBridge did, for diagnosing problems.")
                }
                LabeledContent {
                    Button("Repair…") { SetupCoordinator.shared.present(repair: true) }
                } label: {
                    Text("Setup")
                    Text("Adds the printer and the labelbridge command again.")
                }
                LabeledContent {
                    Button("Uninstall…", role: .destructive) { SetupCoordinator.shared.confirmUninstall() }
                } label: {
                    Text("Uninstall")
                    Text("Removes the printer, the command and the app.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
    }
}
