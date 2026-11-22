import AppKit
import Foundation
import LabelCore

/// Connects to LabelBridge.app, launching it in the background if needed.
enum AppConnection {
    static let unavailableMessage = """
    LabelBridge.app is not available. Install it from the .dmg and open it once. \
    If this command runs in a sandbox (for example an AI agent's), allow access to \
    ~/Library/Application Support/LabelBridge/ and launching apps.
    """

    static func send(_ request: IPCRequest, launch: Bool = true, onProgress: (Int, Int) -> Void) throws -> IPCMessage {
        let client = IPCClient()
        if let msg = try? client.send(request, onProgress: onProgress) { return msg }
        guard launch else { throw IPCError.closed }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", IPCPaths.bundleID]
        try? open.run()
        open.waitUntilExit()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            if let msg = try? client.send(request, onProgress: onProgress) { return msg }
        }
        throw IPCError.closed
    }
}
