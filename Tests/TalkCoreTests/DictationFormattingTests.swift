import XCTest
@testable import TalkCore

final class DictationFormattingTests: XCTestCase {
    func testParagraphRemovesModelListPresentationAndKeepsContent() {
        var settings = TalkSettings(); settings.textBackend = .local; settings.dictationLayout = .paragraph
        let input = "今天有三件事：\n1. 確認權限。\n2. 測試錄音。\n3. 檢查文字插入。"
        let output = TextProcessing.formatOutput(input, action: .dictate, settings: settings)
        XCTAssertFalse(output.contains("\n")); XCTAssertFalse(output.contains("1. "))
        for item in ["確認權限。", "測試錄音。", "檢查文字插入。"] { XCTAssertTrue(output.contains(item)) }
    }
    func testForcedListWrapsOneParagraphAndKeepsItemContinuations() {
        var settings = TalkSettings(); settings.textBackend = .local; settings.dictationLayout = .list
        XCTAssertEqual(TextProcessing.formatOutput("請先確認麥克風權限。", action: .dictate, settings: settings), "1. 請先確認麥克風權限。")
        XCTAssertEqual(TextProcessing.formatOutput("今天有三件事：\n1. 確認權限。\n2. 測試錄音。\n3. 檢查文字\n插入。", action: .dictate, settings: settings),
                       "今天有三件事：\n1. 確認權限。\n2. 測試錄音。\n3. 檢查文字插入。")
    }
    func testProtectedContentAndBypassModesAreUnchanged() {
        var settings = TalkSettings(); settings.textBackend = .local; settings.dictationLayout = .paragraph
        let data = "2026. Amy 使用 API 1.5，預算2,000元，文件 https://example.com/v1.5。"
        XCTAssertEqual(TextProcessing.formatOutput(data, action: .dictate, settings: settings), data)
        let list = "1. 確認權限。\n2. 測試錄音。"
        settings.textBackend = .basic
        XCTAssertEqual(TextProcessing.formatOutput(list, action: .dictate, settings: settings), list)
        settings.textBackend = .local; settings.writingStyle = .verbatim
        XCTAssertEqual(TextProcessing.formatOutput(list, action: .dictate, settings: settings), list)
        settings.writingStyle = .natural
        XCTAssertEqual(TextProcessing.formatOutput(list, action: .ask, settings: settings), list)
    }

    func testAutomaticMixesParagraphsAndListsAndFixesMisrecognitionByContext() {
        var settings = TalkSettings(); settings.textBackend = .local
        let mixed = "今天有幾件事要處理。\n1. 確認權限。\n2. 測試錄音。\n處理完再跟我說。"
        XCTAssertEqual(TextProcessing.formatOutput(mixed, action: .dictate, settings: settings), mixed)
        let prompt = try! TextProcessing.prompt(action: .dictate, transcript: "明天要開會", selection: "", settings: settings)
        XCTAssertTrue(prompt.contains("同一段輸出可同時包含段落與編號列表"))
        XCTAssertTrue(prompt.contains("依上下文修正"))
        XCTAssertTrue(prompt.contains("再來是"))
        XCTAssertTrue(prompt.contains("校稿"))
        XCTAssertTrue(prompt.contains("就是我希望"))
        settings.writingStyle = .verbatim
        XCTAssertFalse(settings.requiresTextModel(for: .dictate))
    }
}
