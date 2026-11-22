import Foundation

/// Compares the running version with the latest GitHub release.
public enum UpdateCheck {
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/hayek/labelbridge/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/hayek/labelbridge/releases")!

    public struct Release: Equatable {
        public let version: String
        public let page: URL
        public let download: URL?
    }

    /// True when `latest` (e.g. "v1.1") is a higher version than `current` (e.g. "1.0").
    /// Missing parts count as 0, so "1.0.0" equals "1.0". Unparseable tags are never newer.
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let l = parts(latest), let c = parts(current) else { return false }
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0, b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// Parses GitHub's "latest release" JSON.
    public static func parseLatest(_ data: Data) throws -> Release {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable { let tag_name: String; let html_url: URL; let assets: [Asset] }
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let dmg = p.assets.first { $0.name.hasSuffix(".dmg") }?.browser_download_url
        return Release(version: strip(p.tag_name), page: p.html_url, download: dmg)
    }

    private static func strip(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    private static func parts(_ version: String) -> [Int]? {
        let nums = strip(version).split(separator: ".").map { Int($0) }
        guard !nums.isEmpty, !nums.contains(where: { $0 == nil }) else { return nil }
        return nums.compactMap { $0 }
    }
}
