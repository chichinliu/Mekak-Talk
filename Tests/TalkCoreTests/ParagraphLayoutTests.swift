import XCTest
@testable import TalkCore

final class ParagraphLayoutTests: XCTestCase {
    private let long = "第一句很快。第二句不穩定。第三句不會分段，希望有列表。第四句越來越長。第五句擠在一起。"

    func testOnlyLongUnbrokenDictationAsksForLayout() {
        XCTAssertTrue(ParagraphLayout.needsLayout(long))
        XCTAssertFalse(ParagraphLayout.needsLayout("第一句。第二句。第三句。"))
        XCTAssertFalse(ParagraphLayout.needsLayout("說明：\n1. 第一項。\n2. 第二項。\n3. 第三項。\n4. 第四項。"))
    }

    func testPromptOnlyAllowsLineBreaksAndTreatsTextAsData() throws {
        let prompt = try ParagraphLayout.prompt(long)
        XCTAssertTrue(prompt.contains("只能在句子之間加入換行"))
        XCTAssertTrue(prompt.hasSuffix(#"{"text":"\#(long)"}"#))
    }

    func testAcceptsOnlyLineBreaksAtSentenceEnds() {
        let laidOut = "第一句很快。第二句不穩定。\n第三句不會分段，\n\n希望有列表。\n\n第四句越來越長。第五句擠在一起。\n"
        XCTAssertEqual(ParagraphLayout.accept(laidOut, original: long),
                       "第一句很快。第二句不穩定。\n\n第三句不會分段，希望有列表。\n\n第四句越來越長。第五句擠在一起。")
    }

    func testRejectsLayoutThatChangesOrAddsText() {
        XCTAssertEqual(ParagraphLayout.accept(long + "\n\n1. 摘要", original: long), long)
        XCTAssertEqual(ParagraphLayout.accept(long.replacingOccurrences(of: "很快", with: "超快"), original: long), long)
        XCTAssertEqual(ParagraphLayout.accept("", original: long), long)
    }
}
