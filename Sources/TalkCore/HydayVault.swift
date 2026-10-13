import Foundation

/// The user's Hyday note folder. Hyday Talk only appends to the end of daily
/// journals, which Hyday merges into an open, unsaved draft; edits anywhere else
/// would make Hyday keep its draft and later overwrite them.
public struct HydayVault: Sendable {
    public let root: URL
    /// Test hook that runs just before the staged file replaces the journal.
    var beforeReplace: (@Sendable (URL) -> Void)?

    public init(root: URL) { self.root = root }

    public static var defaultSettingsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hyday/settings.json")
    }

    /// Reads `vault.root`; the top-level `journalPath` key is Hyday's retired v1 setting.
    public static func configuredRoot(settingsFile: URL = defaultSettingsFile) -> URL? {
        guard let data = try? Data(contentsOf: settingsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vault = json["vault"] as? [String: Any],
              let path = vault["root"] as? String, path.hasPrefix("/") else { return nil }
        return isDirectory(URL(fileURLWithPath: path)) ? URL(fileURLWithPath: path) : nil
    }

    public static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    /// Spoken text without AI classification becomes one plain list item.
    public static func bullet(_ text: String) -> String {
        "- " + text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    public func journalURL(for date: Date, calendar: Calendar = .current) -> URL {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(format: "%04d", parts.year ?? 0)
        let name = String(format: "%04d-%02d-%02d.md", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return root.appendingPathComponent("journal").appendingPathComponent(year).appendingPathComponent(name)
    }

    /// Appends Markdown to the end of the day's journal, creating it from the
    /// journal template when needed. The write is locked, staged and swapped in
    /// atomically, and retried if the file changed while the entry was composed.
    @discardableResult
    public func appendToJournal(_ markdown: String, at date: Date = Date(), calendar: Calendar = .current) throws -> URL {
        let url = journalURL(for: date, calendar: calendar)
        let folder = url.deletingLastPathComponent()
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw TalkError("Hyday 資料夾路徑無效。") }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { throw TalkError("無法建立 Hyday 日誌資料夾，請確認資料夾權限。") }
        let lock = open(folder.path, O_RDONLY)
        guard lock >= 0 else { throw TalkError("無法開啟 Hyday 日誌資料夾，請確認資料夾權限。") }
        defer { flock(lock, LOCK_UN); close(lock) }
        flock(lock, LOCK_EX)
        let stamp = Self.timestamp(date, calendar: calendar)
        for _ in 0..<5 {
            let original = try? Data(contentsOf: url)
            let base = original.flatMap { String(data: $0, encoding: .utf8) } ?? newJournal(stamp: stamp)
            let updated = Self.appending(markdown, to: base, stamp: stamp)
            let staging = folder.appendingPathComponent(".hyday-talk-\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: staging) }
            do { try Data(updated.utf8).write(to: staging) }
            catch { throw TalkError("無法寫入 Hyday 日誌，請確認磁碟空間與資料夾權限。") }
            beforeReplace?(url)
            // Only swap in the staged file if nobody changed the journal meanwhile.
            guard (try? Data(contentsOf: url)) == original else { continue }
            guard rename(staging.path, url.path) == 0 else { throw TalkError("無法寫入 Hyday 日誌，請確認資料夾權限。") }
            return url
        }
        throw TalkError("Hyday 日誌持續被修改，請稍後再試。")
    }

    private func newJournal(stamp: String) -> String {
        let template = root.appendingPathComponent("templates/journal.md")
        guard let text = try? String(contentsOf: template, encoding: .utf8) else {
            return "---\ncreatedAt: \(stamp)\nlastModified: \(stamp)\n---\n"
        }
        return Self.setting(field: "createdAt", to: stamp, in: text)
    }

    static func appending(_ markdown: String, to text: String, stamp: String) -> String {
        var body = setting(field: "lastModified", to: stamp, in: text)
        // Follow the journal's own list marker so the new lines match.
        let marker = body.split(separator: "\n").first { $0.hasPrefix("* ") || $0.hasPrefix("- ") }?.prefix(1) ?? "-"
        let entry = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            marker == "*" && line.hasPrefix("- ") && !line.hasPrefix("- [") ? "* " + line.dropFirst(2) : Substring(line)
        }.joined(separator: "\n").trimmingCharacters(in: .newlines)
        while body.hasSuffix("\n") { body.removeLast() }
        return body + "\n\n" + entry + "\n"
    }

    /// Sets a frontmatter field, adding frontmatter or the field when missing.
    static func setting(field: String, to value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
            return "---\ncreatedAt: \(value)\nlastModified: \(value)\n---\n" + text
        }
        if let index = lines[1..<end].firstIndex(where: { $0.hasPrefix(field + ":") }) {
            lines[index] = "\(field): \(value)"
        } else {
            lines.insert("\(field): \(value)", at: end)
            if field == "createdAt", !lines[1...end].contains(where: { $0.hasPrefix("lastModified:") }) {
                lines.insert("lastModified: \(value)", at: end + 1)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Hyday writes `YYYY-MM-DD HH:mm:ss` in local time.
    static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
