import AppKit
import LabelCore

/// Hidden developer mode: `LabelBridge --debug-print "<text>" <count> <copies>`.
enum DebugPrint {
    @MainActor
    static func run(text: String, count: Int, copies: Int) async -> Int32 {
        let scanner = PrinterScanner()
        do {
            let link = try await scanner.connect()
            let pages = (1...max(count, 1)).map { i -> EncodedPage in
                let label = count > 1 ? "\(text) \(i)" : text
                let bitmap = TextRenderer.render(label, size: .defaultSize, style: TextStyle()).bitmap
                return RowEncoder.encode(link.profile.prepare(bitmap), profile: link.profile)
            }
            Log.write("debug-print: connected, \(pages.count) page(s) × \(copies)")
            let printed = try await PrintSession(link: link).run(pages: pages, settings: PrintSettings(density: 3, copies: copies)) { done, total in
                Log.write("debug-print: progress \(done)/\(total)")
            }
            await link.close()
            Log.write("debug-print: done, printed \(printed)")
            return 0
        } catch {
            Log.write("debug-print: failed \(error)")
            return 1
        }
    }
}
