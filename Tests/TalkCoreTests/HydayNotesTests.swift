import XCTest
@testable import TalkCore

final class HydayNotesTests: XCTestCase {
    private var root: URL!
    private func write(_ text: String, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("hyday-notes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testSplitsQueriesIntoWordsAndChineseBigrams() {
        XCTAssertEqual(HydayNoteSearch.terms("專案 Kickoff，會議紀錄"), ["專案", "kickoff", "會議", "議紀", "紀錄"])
        XCTAssertEqual(HydayNoteSearch.terms("貓"), ["貓"])
    }

    func testRanksNotesByMatchedTermsAndUsesFrontmatterTitles() throws {
        try write("---\ntitle: 季度規劃\n---\n這季的專案會議決定改版首頁。\n", to: "work/plan.md")
        try write("# 雜記\n今天提到專案一次。\n", to: "misc/雜記.md")
        try write("與專案無關的內容\n", to: "notes/other.txt")
        let results = try HydayNoteSearch.search(root: root, query: "專案會議")
        XCTAssertEqual(results.map(\.path), ["work/plan.md", "misc/雜記.md"])
        XCTAssertEqual(results.map(\.title), ["季度規劃", "雜記"])
        XCTAssertTrue(results[0].snippet.contains("專案會議"))
        XCTAssertFalse(results[0].snippet.contains("title:"))
    }

    func testSkipsHydayInternalWikiAndHiddenFolders() throws {
        try write("咖啡豆筆記", to: ".hyday/cache.md")
        try write("咖啡豆筆記", to: "hyday-wiki/index.md")
        try write("咖啡豆筆記", to: ".trash/old.md")
        try write("咖啡豆筆記", to: "food/coffee.md")
        XCTAssertEqual(try HydayNoteSearch.search(root: root, query: "咖啡豆").map(\.path), ["food/coffee.md"])
    }

    func testSnippetsAreTruncatedAroundTheMatch() throws {
        try write(String(repeating: "填充文字。", count: 200) + "關鍵咖啡豆在這裡" + String(repeating: "後續內容。", count: 200), to: "long.md")
        let note = try XCTUnwrap(HydayNoteSearch.search(root: root, query: "咖啡豆").first)
        XCTAssertTrue(note.snippet.contains("咖啡豆"))
        XCTAssertLessThanOrEqual(note.snippet.count, 240)
    }

    func testReturnsNothingWithoutMatches() throws {
        try write("今天天氣很好", to: "a.md")
        XCTAssertTrue(try HydayNoteSearch.search(root: root, query: "量子電腦").isEmpty)
    }

    func testCollectsEntitiesAndTagsOutsideCode() {
        let text = """
        和 @(王小明) 討論 #工作/專案，也提到 @{舊人名}。
        email@(不是) 與 #123 不算，行首 #Hyday 算
        ```
        @(程式碼人) #codeTag
        ```
        行內 `@(行內) #inline` 不算
        """
        XCTAssertEqual(HydayVocabulary.terms(in: text), ["王小明", "工作/專案", "舊人名", "Hyday"])
    }

    func testScansTheFolderWithoutHydayInternalFolders() throws {
        try write("@(王小明) #旅行", to: "journal/2026/2026-10-13.md")
        try write("@(王小明) #閱讀", to: "notes/book.md")
        try write("@(內部) #內部", to: ".hyday/index.md")
        try write("@(維基) #維基", to: "hyday-wiki/page.md")
        XCTAssertEqual(try HydayVocabulary.scan(root: root), ["王小明", "旅行", "閱讀"])
    }

    func testRecognitionHintsPutManualThenNewestLearnedThenHydayAndCap() {
        let dictionary = [DictionaryEntry(term: "舊學到", isAutomatic: true), DictionaryEntry(term: "Hyday"),
                          DictionaryEntry(term: "新學到", isAutomatic: true)]
        XCTAssertEqual(RecognitionHints.terms(dictionary: dictionary, vocabulary: ["Hyday", "王小明"], limit: 10),
                       ["Hyday", "新學到", "舊學到", "王小明"])
        XCTAssertEqual(RecognitionHints.terms(dictionary: dictionary, vocabulary: ["王小明"], limit: 2), ["Hyday", "新學到"])
    }

    func testAskPromptCarriesReferenceNotesAndLinkInstructions() throws {
        let notes = [HydayNote(title: "季度規劃", path: "work/plan.md", snippet: "這季的專案會議決定改版首頁")]
        let prompt = try TextProcessing.prompt(action: .ask, transcript: "首頁要改什麼", selection: "", settings: TalkSettings(), notes: notes)
        XCTAssertTrue(prompt.contains("[[筆記名稱]]"))
        XCTAssertTrue(prompt.contains("\"reference_notes\""))
        XCTAssertTrue(prompt.contains("這季的專案會議決定改版首頁"))
        XCTAssertTrue(prompt.contains("work\\/plan.md") || prompt.contains("work/plan.md"))
        let empty = try TextProcessing.prompt(action: .ask, transcript: "首頁要改什麼", selection: "", settings: TalkSettings(), notes: [])
        XCTAssertTrue(empty.contains("沒有找到相關筆記"))
        let off = try TextProcessing.prompt(action: .ask, transcript: "首頁要改什麼", selection: "", settings: TalkSettings())
        XCTAssertFalse(off.contains("reference_notes"))
    }

    func testAskNotesSettingDefaultsOffForOldSettings() throws {
        let old = try JSONDecoder().decode(TalkSettings.self, from: JSONEncoder().encode(TalkSettings()))
        XCTAssertFalse(old.asksHydayNotes)
    }

}
