import AppKit

let arguments = CommandLine.arguments
Log.write("launch args: \(arguments.dropFirst().joined(separator: " "))")
if let i = arguments.firstIndex(of: "--debug-print"), arguments.count > i + 1 {
    let text = arguments[i + 1]
    let count = arguments.count > i + 2 ? Int(arguments[i + 2]) ?? 1 : 1
    let copies = arguments.count > i + 3 ? Int(arguments[i + 3]) ?? 1 : 1
    Task { @MainActor in exit(await DebugPrint.run(text: text, count: count, copies: copies)) }
    RunLoop.main.run()
}
// The window app is added in Task 6.
