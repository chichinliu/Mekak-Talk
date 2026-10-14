import XCTest
@testable import TalkCore

final class HintEchoTests: XCTestCase {
    let hints = ["Hyday", "Ethan", "Zoe", "Vito", "禹掄", "義倫", "Alan", "開發日誌", "projects/Hyday", "Bruce",
                 "idea", "projects/家居裝潢", "areas/家庭育兒", "祐祐", "睿睿", "thought", "quote"]

    func testHierarchicalTagsKeepOnlyTheirLastPart() {
        let terms = RecognitionHints.terms(dictionary: [], vocabulary: ["projects/Hyday", "Hyday", "areas/家庭育兒", "projects/家居裝潢"])
        XCTAssertEqual(terms, ["Hyday", "家庭育兒", "家居裝潢"])
    }

    func testTranscriptThatRepeatsTheHintListIsAnEcho() {
        let echo = "Hyday Ethan Zoe Vito 禹掄 義倫 Alan 開發日誌 projects/Hyday Bruce idea projects/家居裝潢 areas/家庭育兒"
        XCTAssertTrue(RecognitionHints.isEcho(echo, hints: hints))
    }

    func testNormalSpeechMentioningAFewHintsIsNotAnEcho() {
        XCTAssertFalse(RecognitionHints.isEcho("Hyday", hints: hints))
        XCTAssertFalse(RecognitionHints.isEcho("明天找 Ethan 和 Zoe 討論 Hyday 的開發日誌", hints: hints))
        XCTAssertFalse(RecognitionHints.isEcho("Hyday Ethan", hints: hints))
    }
}
