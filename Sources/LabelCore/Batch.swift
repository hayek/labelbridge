import Foundation

public enum Batch {
    /// One label per line. A literal `\n` inside a line becomes a line break on that label.
    /// Blank and whitespace-only lines are skipped.
    public static func items(from text: String) -> (items: [String], skipped: Int) {
        items(from: lines(from: text))
    }

    /// Splits text into lines, accepting \n, \r\n and \r endings. Trailing empty lines
    /// (a final newline, or empty input) are dropped, so they don't count as skipped labels.
    public static func lines(from text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines
    }

    public static func items(from lines: [String]) -> (items: [String], skipped: Int) {
        var items: [String] = []
        var skipped = 0
        for line in lines {
            let item = line.replacingOccurrences(of: "\\n", with: "\n")
            if item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { skipped += 1 } else { items.append(item) }
        }
        return (items, skipped)
    }
}
