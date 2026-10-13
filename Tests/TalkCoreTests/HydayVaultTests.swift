import XCTest
@testable import TalkCore

final class HydayVaultTests: XCTestCase {
    private var root: URL!
    private let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Taipei")!; return c }()
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: hour, minute: minute))!
    }
    private var journal: URL { root.appendingPathComponent("journal/2026/2026-10-13.md") }
    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hyday-vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testResolvesTheFolderFromHydaySettings() throws {
        let settings = root.appendingPathComponent("settings.json")
        try write(#"{"vault":{"root":"\#(root.path)"},"journalPath":"/old"}"#, to: settings)
        XCTAssertEqual(HydayVault.configuredRoot(settingsFile: settings)?.standardizedFileURL, root.standardizedFileURL)
        try write(#"{"journalPath":"\#(root.path)"}"#, to: settings)
        XCTAssertNil(HydayVault.configuredRoot(settingsFile: settings))
        try write(#"{"vault":{"root":"/missing/hyday"}}"#, to: settings)
        XCTAssertNil(HydayVault.configuredRoot(settingsFile: settings))
        XCTAssertNil(HydayVault.configuredRoot(settingsFile: root.appendingPathComponent("absent.json")))
    }

    func testAppendsToTheEndOfAnExistingJournalAndKeepsFrontmatter() throws {
        try write("---\ncreatedAt: 2026-10-13 09:00:00\nlastModified: 2026-10-13 09:00:00\nmood: 好\n---\n* 早上散步\n%(想法)\n", to: journal)
        let url = try HydayVault(root: root).appendToJournal("- 下午開會", at: date(14, 32), calendar: calendar)
        XCTAssertEqual(url.standardizedFileURL, journal.standardizedFileURL)
        XCTAssertEqual(try read(journal), "---\ncreatedAt: 2026-10-13 09:00:00\nlastModified: 2026-10-13 14:32:00\nmood: 好\n---\n* 早上散步\n%(想法)\n\n* 下午開會\n")
    }

    func testCreatesTheJournalWhenItDoesNotExist() throws {
        try HydayVault(root: root).appendToJournal("- 第一筆\n- [ ] 回信", at: date(8, 5), calendar: calendar)
        XCTAssertEqual(try read(journal), "---\ncreatedAt: 2026-10-13 08:05:00\nlastModified: 2026-10-13 08:05:00\n---\n\n- 第一筆\n- [ ] 回信\n")
    }

    func testNewJournalUsesTheJournalTemplate() throws {
        try write("---\ncreatedAt: x\nlastModified: x\ntags: [日誌]\n---\n## 今天\n", to: root.appendingPathComponent("templates/journal.md"))
        try HydayVault(root: root).appendToJournal("- 筆記", at: date(8, 5), calendar: calendar)
        XCTAssertEqual(try read(journal), "---\ncreatedAt: 2026-10-13 08:05:00\nlastModified: 2026-10-13 08:05:00\ntags: [日誌]\n---\n## 今天\n\n- 筆記\n")
    }

    func testKeepsAnEditMadeWhileTheEntryWasBeingWritten() throws {
        try write("---\nlastModified: 2026-10-13 09:00:00\n---\n- 原本\n", to: journal)
        var vault = HydayVault(root: root)
        var interfered = false
        vault.beforeReplace = { url in
            guard !interfered else { return }; interfered = true
            try? "---\nlastModified: 2026-10-13 09:00:00\n---\n- 原本\n- 別人加的\n".write(to: url, atomically: true, encoding: .utf8)
        }
        try vault.appendToJournal("- 新的", at: date(10), calendar: calendar)
        XCTAssertEqual(try read(journal), "---\nlastModified: 2026-10-13 10:00:00\n---\n- 原本\n- 別人加的\n\n- 新的\n")
    }

    func testFlattensSpeechIntoOneBullet() {
        XCTAssertEqual(HydayVault.bullet("  記得\n回信  "), "- 記得 回信")
    }
}
