import Foundation

/// A newer release published on GitHub, with the DMG to download.
public struct AppUpdate: Equatable, Sendable {
    public let version: String
    public let dmg: URL
    public let page: URL

    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/mukiwu/hyday-talk/releases/latest")!

    /// Reads GitHub's latest-release JSON; nil unless it is newer than `current` and carries a DMG.
    public static func parse(_ data: Data, current: String) -> AppUpdate? {
        struct Release: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String; let html_url: URL; let draft: Bool?; let prerelease: Bool?; let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data),
              release.draft != true, release.prerelease != true else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard isNewer(version, than: current),
              let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else { return nil }
        return AppUpdate(version: version, dmg: asset.browser_download_url, page: release.html_url)
    }

    /// Compares dotted versions numerically, so 0.1.10 is newer than 0.1.9.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parts = { (text: String) in text.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
