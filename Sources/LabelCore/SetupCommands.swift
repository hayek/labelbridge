import Foundation

/// Commands used by first-launch setup, kept pure so they can be tested.
public enum SetupCommands {
    public static let queueName = "NIIMBOT_D11"
    public static let queueDescription = "NIIMBOT D11 (Bluetooth)"
    public static let cliLink = "/usr/local/bin/labelbridge"

    public static func addQueueArguments(ppdPath: String) -> [String] {
        ["-p", queueName, "-D", queueDescription, "-L", "via LabelBridge", "-E",
         "-v", "socket://127.0.0.1:9183", "-P", ppdPath, "-o", "printer-is-shared=false"]
    }

    public static func installCLICommand(helperPath: String) -> String {
        "mkdir -p \(quote("/usr/local/bin")) && ln -sf \(quote(helperPath)) \(quote(cliLink))"
    }

    public static func removeCLICommand() -> String { "rm -f \(quote(cliLink))" }

    public static func isInApplications(_ bundlePath: String) -> Bool {
        bundlePath.hasPrefix("/Applications/") && !bundlePath.contains("/AppTranslocation/")
    }

    /// Single-quotes for /bin/sh.
    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
