import Foundation
import Network
import LabelCore

/// Receives Print-dialog jobs from the CUPS queue (socket://127.0.0.1:9183).
/// Only PDF data is accepted; anything else is dropped, so this is not an API.
enum CUPSListener {
    static let port: NWEndpoint.Port = 9183
    private static var listener: NWListener?

    static func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { accept($0) }
            l.stateUpdateHandler = { Log.write("CUPS listener: \($0)") }
            l.start(queue: .main)
            listener = l
        } catch {
            Log.write("CUPS listener failed: \(error)")
        }
    }

    private static func accept(_ c: NWConnection) {
        var buffer = Data()
        c.start(queue: .main)
        func read() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, done, error in
                if let data { buffer.append(data) }
                if buffer.count >= 4, !buffer.starts(with: Array("%PDF".utf8)) { c.cancel(); return }
                if done || error != nil { Task { @MainActor in await handle(buffer); c.cancel() } } else { read() }
            }
        }
        read()
    }

    @MainActor
    private static func handle(_ data: Data) async {
        let size = PDFLabels.labelSize(of: data) ?? Settings.labelSize
        do {
            let bitmaps = try PDFLabels.bitmaps(from: data, size: size)
            Log.write("CUPS job: \(bitmaps.count) page(s)")
            let r = await PrintService.shared.print(bitmaps: bitmaps, settings: PrintSettings(density: Settings.density, copies: 1, media: Settings.media))
            if !r.ok {
                let done = r.printed > 0 ? " \(r.printed) of \(r.total) labels printed." : ""
                Notifier.post(title: "Couldn't print to the NIIMBOT D11", body: (r.error ?? "Printing failed.") + done)
            }
        } catch {
            Log.write("CUPS job rejected: \(error)")
            Notifier.post(title: "Couldn't print to the NIIMBOT D11", body: "LabelBridge couldn't read the document from the Print dialog.")
        }
    }
}
