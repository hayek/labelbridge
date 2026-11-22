import Foundation

public enum Batch {
    /// One label per line. A literal `\n` inside a line becomes a line break on that label.
    /// Blank and whitespace-only lines are skipped.
    public static func items(from text: String) -> (items: [String], skipped: Int) {
        var lines = text.components(separatedBy: .newlines)
        // Trailing empty lines (a final newline, or empty input) aren't skipped labels.
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return items(from: lines)
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
