import XCTest
@testable import TalkCore

final class CorrectionFinderTests: XCTestCase {
    private func pairs(_ inserted: String, _ following: String) -> [String] {
        CorrectionFinder.find(inserted: inserted, following: following).map { "\($0.original)→\($0.corrected)" }
    }

    func testReplacedWordsAreCorrections() {
        XCTAssertEqual(pairs("請 Haidai 和 Jeny 明天開會。", "請 Hyday 和 Jenny 明天開會。"), ["Haidai→Hyday", "Jeny→Jenny"])
        XCTAssertEqual(pairs("記得找海帶討論。", "記得找Hyday討論。"), ["海帶→Hyday"])
    }

    func testCaseOnlyChangeCounts() {
        XCTAssertEqual(pairs("程式放在 github 上。", "程式放在 GitHub 上。"), ["github→GitHub"])
    }

    func testTextTypedAfterTheInsertionIsIgnored() {
        XCTAssertEqual(pairs("請 Haidai 確認。", "請 Hyday 確認。另外我晚點再補充細節"), ["Haidai→Hyday"])
    }

    func testDeletionsPunctuationAndRewritesAreNotCorrections() {
        XCTAssertEqual(pairs("明天下午開會，記得帶報告。", "明天開會，記得帶報告。"), [])
        XCTAssertEqual(pairs("明天下午開會，記得帶報告。", "明天下午開會。記得帶報告！"), [])
        XCTAssertEqual(pairs("明天下午開會，記得帶報告。", "下週再說吧"), [])
        XCTAssertEqual(pairs("明天下午開會。", "明天下午開會。"), [])
    }

    func testLongReplacementsAreNotCorrections() {
        XCTAssertEqual(pairs("請確認文件。", "請確認這份非常非常長而且完全不同的新版規格文件。"), [])
    }

    func testMoreThanThreeChangesIsTreatedAsRewrite() {
        XCTAssertEqual(pairs("甲找乙和丙談丁的事。", "子找丑和寅談卯的事。"), [])
        XCTAssertEqual(pairs("A 找 B 和 C 談 D 的事。", "W 找 X 和 Y 談 Z 的事。"), [])
    }

    func testCorrectionAtTheVeryEndIsFound() {
        XCTAssertEqual(pairs("請確認 Haidai", "請確認 Hyday"), ["Haidai→Hyday"])
        XCTAssertEqual(pairs("請確認 Haidai", "請確認 Hyday 再回覆我"), ["Haidai→Hyday"])
    }

    func testCorrectionKeepsSurroundingSentenceForJudging() {
        let found = CorrectionFinder.find(inserted: "記得找海帶討論。", following: "記得找Hyday討論。")
        XCTAssertEqual(found.first?.context, "記得找Hyday討論。")
    }
}

final class DictionaryLearningTests: XCTestCase {
    func testLearnsNewCorrectionAsAutomaticEntry() {
        var settings = TalkSettings()
        DictionaryLearning.learn(Correction(original: "Haidai", corrected: "Hyday", context: ""), into: &settings)
        XCTAssertEqual(settings.dictionary.map(\.heard), ["Haidai"])
        XCTAssertEqual(settings.dictionary.first?.replacement, "Hyday")
        XCTAssertTrue(settings.dictionary.first?.isAutomatic == true)
        DictionaryLearning.learn(Correction(original: "Haidai", corrected: "Hyday", context: ""), into: &settings)
        XCTAssertEqual(settings.dictionary.count, 1)
    }

    func testLatestCorrectionOverwritesAutomaticButNeverManualEntries() {
        var settings = TalkSettings()
        DictionaryLearning.learn(Correction(original: "Haidai", corrected: "Hyday", context: ""), into: &settings)
        DictionaryLearning.learn(Correction(original: "Haidai", corrected: "HyDay", context: ""), into: &settings)
        XCTAssertEqual(settings.dictionary.map(\.replacement), ["HyDay"])
        settings.dictionary = [DictionaryEntry(heard: "Jeny", replacement: "Jennie")]
        DictionaryLearning.learn(Correction(original: "Jeny", corrected: "Jenny", context: ""), into: &settings)
        XCTAssertEqual(settings.dictionary.map(\.replacement), ["Jennie"])
        XCTAssertFalse(settings.dictionary[0].isAutomatic)
    }

    func testRemovedAutomaticEntryIsNeverLearnedAgain() {
        var settings = TalkSettings()
        DictionaryLearning.learn(Correction(original: "Haidai", corrected: "Hyday", context: ""), into: &settings)
        DictionaryLearning.remove(settings.dictionary[0], from: &settings)
        XCTAssertTrue(settings.dictionary.isEmpty)
        DictionaryLearning.learn(Correction(original: "Haidai", corrected: "Hyday", context: ""), into: &settings)
        XCTAssertTrue(settings.dictionary.isEmpty)
        settings.dictionary.append(DictionaryEntry(heard: "Haidai", replacement: "Hyday"))
        XCTAssertEqual(settings.dictionary.count, 1)
    }

    func testBlockListHasNoDuplicatesAndStaysBounded() {
        var settings = TalkSettings()
        for index in 0..<(DictionaryLearning.blockLimit + 20) {
            DictionaryLearning.learn(Correction(original: "詞\(index)", corrected: "Term\(index)", context: ""), into: &settings)
            DictionaryLearning.remove(settings.dictionary[0], from: &settings)
        }
        DictionaryLearning.learn(Correction(original: "詞999", corrected: "Term999", context: ""), into: &settings)
        let duplicate = DictionaryEntry(heard: "詞999", replacement: "Term999", isAutomatic: true)
        DictionaryLearning.remove(settings.dictionary[0], from: &settings)
        DictionaryLearning.remove(duplicate, from: &settings)
        XCTAssertEqual(settings.blockedCorrections?.count, DictionaryLearning.blockLimit)
        XCTAssertEqual(settings.blockedCorrections?.filter { $0.heard == "詞999" }.count, 1)
    }

    func testDictionaryMatchesAfterSimplifiedOutputIsConverted() {
        var settings = TalkSettings(); settings.textBackend = .local
        settings.dictionary = [DictionaryEntry(heard: "海帶", replacement: "Hyday")]
        XCTAssertEqual(TextProcessing.formatOutput("找海带讨论。", action: .dictate, settings: settings), "找Hyday討論。")
    }

    func testLearningIsOnByDefaultAndOldSettingsStillDecode() throws {
        XCTAssertTrue(TalkSettings().learnsFromCorrections)
        let legacy = #"{"speechBackend":"whisper","textBackend":"local","locale":"zh-TW","targetLanguage":"英文","writingStyle":"natural","systemOfflineOnly":false,"autoInsert":true,"saveHistory":true,"interactionSounds":true,"whisperExecutable":"","whisperModel":"","speechCLIExecutable":"","speechCLIArguments":"","textCLIExecutable":"","textCLIArguments":"","speechAPI":{"baseURL":"https://api.openai.com/v1","model":"m"},"textAPI":{"baseURL":"https://api.openai.com/v1","model":"m"},"dictionary":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","heard":"海帶","replacement":"Hyday"}]}"#
        let decoded = try JSONDecoder().decode(TalkSettings.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.learnsFromCorrections)
        XCTAssertFalse(decoded.dictionary[0].isAutomatic)
    }

    func testDictionaryAlsoAppliesToTextAfterAI() {
        var settings = TalkSettings(); settings.textBackend = .local
        settings.dictionary = [DictionaryEntry(heard: "Haidai", replacement: "Hyday")]
        XCTAssertEqual(TextProcessing.formatOutput("請 Haidai 確認。", action: .dictate, settings: settings), "請 Hyday 確認。")
    }
}

final class CorrectionJudgeTests: XCTestCase {
    func testPromptCarriesCorrectionAsDataAndAnswerIsParsed() throws {
        let prompt = try CorrectionJudge.prompt(for: Correction(original: "海帶", corrected: "Hyday", context: "記得找Hyday討論。"))
        XCTAssertTrue(prompt.contains("專有名稱")); XCTAssertTrue(prompt.contains("人名"))
        XCTAssertTrue(prompt.contains("Hyday")); XCTAssertTrue(prompt.contains("記得找Hyday討論。"))
        XCTAssertTrue(CorrectionJudge.isTerm("是"))
        XCTAssertTrue(CorrectionJudge.isTerm("是。"))
        XCTAssertFalse(CorrectionJudge.isTerm("否"))
        XCTAssertFalse(CorrectionJudge.isTerm("我不確定"))
    }
}
