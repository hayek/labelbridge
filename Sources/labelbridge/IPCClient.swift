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
        do { return try client.send(request, onProgress: onProgress) }
        catch IPCError.notRunning where launch {}   // only relaunch when the app isn't there; never resend a job it received
        
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-b", IPCPaths.bundleID]
        try? open.run()
        open.waitUntilExit()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
            do { return try client.send(request, onProgress: onProgress) }
            catch IPCError.notRunning { continue }
        }
        throw IPCError.notRunning
    }
}
