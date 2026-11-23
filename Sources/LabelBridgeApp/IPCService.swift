import Foundation
import LabelCore

/// Answers `labelbridge` CLI requests on the private socket.
enum IPCService {
    private static var server: IPCServer?

    static func start() {
        do {
            server = try IPCServer(path: IPCPaths.socketURL.path) { request, send in
                switch request {
                case .print(let job):
                    let result = await PrintService.shared.print(job) { done, total in send(.progress(done, total)) }
                    send(.result(result))
                case .printSticker(let job):
                    let result = await PrintService.shared.print(job) { done, total in send(.progress(done, total)) }
                    send(.result(result))
                case .status:
                    let info = await MainActor.run { () -> StatusInfo in
                        let s = PrintService.shared
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                        return StatusInfo(appVersion: version, printer: s.statusText, queued: s.queued)
                    }
                    send(.status(info))
                }
            }
            Log.write("IPC listening at \(IPCPaths.socketURL.path)")
        } catch {
            Log.write("IPC failed to start: \(error)")
        }
    }
}
