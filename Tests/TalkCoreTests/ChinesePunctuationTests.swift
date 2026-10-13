import XCTest
@testable import TalkCore

final class ChinesePunctuationTests: XCTestCase {
    func testTraditionalChineseUsesFullWidthSentencePunctuation() {
        XCTAssertEqual(TextProcessing.clean("你好, 今天開會嗎? 會議在下午三點. (請準時); 謝謝!", settings: TalkSettings()),
                       "你好，今天開會嗎？會議在下午三點。（請準時）；謝謝！")
    }

    func testChinesePunctuationPreservesNumbersAndTechnicalTokens() {
        let input = "價格 1,234.56 元, 版本 v1.2.3, 時間 09:30, 網址 https://example.com/a?x=1, 信箱 test@example.com."
        let expected = "價格 1,234.56 元，版本 v1.2.3，時間 09:30，網址 https://example.com/a?x=1，信箱 test@example.com。"
        XCTAssertEqual(TextProcessing.clean(input, settings: TalkSettings()), expected)
    }

    func testEnglishSentencesAndInlineCodeKeepTheirPunctuation() {
        let input = "Hello, world! 你好, 世界! 請使用 `print(\"hi, there!\")`, 然後完成."
        let expected = "Hello, world! 你好，世界！請使用 `print(\"hi, there!\")`，然後完成。"
        XCTAssertEqual(TextProcessing.clean(input, settings: TalkSettings()), expected)
        var english = TalkSettings(); english.locale = "en-US"
        XCTAssertEqual(TextProcessing.clean("Hello, world! (OK)", settings: english), "Hello, world! (OK)")
    }

    func testAdjacentNumbersEmojiAndQuotedSpeech() {
        XCTAssertEqual(TextProcessing.clean("價格1,234.56元,時間09:30,😊你好!", settings: TalkSettings()),
                       "價格1,234.56元，時間09:30，😊你好！")
        XCTAssertEqual(TextProcessing.clean("他說 \"Hello, world!\", 我回答 \"你好!\".", settings: TalkSettings()),
                       "他說 「Hello, world!」，我回答 「你好！」。")
    }

    func testFencedCodeRetainsChineseCommentsAndSpacing() {
        let code = "```swift\n// 中文， 註解\nprint(\"你好, 世界!\")\n```"
        XCTAssertEqual(TextProcessing.clean("範例:\n" + code + "\n結束.", settings: TalkSettings()),
                       "範例：\n" + code + "\n結束。")
    }

    func testFinalAIOutputAndTranslationFollowOutputLanguage() {
        var settings = TalkSettings()
        XCTAssertEqual(TextProcessing.formatOutput("你好, 世界!", action: .dictate, settings: settings), "你好，世界！")
        XCTAssertEqual(TextProcessing.formatOutput("你好, 世界!", action: .ask, settings: settings), "你好，世界！")
        XCTAssertEqual(TextProcessing.formatOutput("Hello, world! (OK)", action: .translate, settings: settings), "Hello, world! (OK)")
        settings.locale = "en-US"; settings.targetLanguage = "台灣繁體中文"
        XCTAssertEqual(TextProcessing.formatOutput("价格1,234.56元, 谢谢!", action: .translate, settings: settings), "價格1,234.56元，謝謝！")
    }
}
