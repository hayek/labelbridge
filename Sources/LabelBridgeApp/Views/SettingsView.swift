import SwiftUI
import LabelCore

struct SettingsView: View {
    @State private var openAtLogin = Settings.openAtLogin

    var body: some View {
        Form {
            Toggle("Open at login (hidden), so the command line and Print dialog always work", isOn: $openAtLogin)
                .onChange(of: openAtLogin) { Settings.openAtLogin = $0; LoginItem.apply($0) }
            Text("Default label size, darkness, font and alignment are remembered from the main window.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Open Log") { NSWorkspace.shared.open(Log.url) }
                Button("Repair Setup…") { SetupCoordinator.shared.present(repair: true) }
                Button("Uninstall…") { SetupCoordinator.shared.confirmUninstall() }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
