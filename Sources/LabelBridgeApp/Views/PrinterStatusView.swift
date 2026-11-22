import SwiftUI

/// Live printer status: on and nearby, still looking, printing, or a Bluetooth problem.
struct PrinterStatusView: View {
    @ObservedObject var service = PrintService.shared

    var body: some View {
        let status = service.printerStatus
        HStack(spacing: 12) {
            Image(systemName: "printer.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint(status.kind))
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint(status.kind).opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title).font(.body.weight(.medium))
                Text(status.detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            indicator(status.kind)
        }
        .animation(.default, value: status)
        .onAppear { service.watchPrinter(true) }
        .onDisappear { service.watchPrinter(false) }
    }

    private func tint(_ kind: PrinterStatus.Kind) -> Color {
        switch kind {
        case .ready: return .green
        case .busy: return .accentColor
        case .searching: return .secondary
        case .problem: return .orange
        }
    }

    @ViewBuilder private func indicator(_ kind: PrinterStatus.Kind) -> some View {
        switch kind {
        case .ready: Circle().fill(.green).frame(width: 9, height: 9)
        case .searching, .busy: ProgressView().controlSize(.small)
        case .problem: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
    }
}
