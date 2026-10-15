import XCTest
@testable import TalkCore

final class AppUpdateTests: XCTestCase {
    private func release(_ tag: String, assets: String = #"[{"name":"Hyday-Talk-0.1.4.dmg","browser_download_url":"https://example.com/a.dmg"}]"#,
                         prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"https://example.com/r","draft":false,"prerelease":\#(prerelease),"assets":\#(assets)}"#.utf8)
    }

    func testNewerReleaseWithDMGIsOffered() {
        let update = AppUpdate.parse(release("v0.1.4"), current: "0.1.3")
        XCTAssertEqual(update?.version, "0.1.4")
        XCTAssertEqual(update?.dmg, URL(string: "https://example.com/a.dmg"))
    }

    func testSameOlderPrereleaseOrMissingDMGIsIgnored() {
        XCTAssertNil(AppUpdate.parse(release("v0.1.3"), current: "0.1.3"))
        XCTAssertNil(AppUpdate.parse(release("v0.1.2"), current: "0.1.3"))
        XCTAssertNil(AppUpdate.parse(release("v0.2.0", prerelease: true), current: "0.1.3"))
        XCTAssertNil(AppUpdate.parse(release("v0.2.0", assets: "[]"), current: "0.1.3"))
    }

    func testVersionsCompareNumerically() {
        XCTAssertTrue(AppUpdate.isNewer("0.1.10", than: "0.1.9"))
        XCTAssertTrue(AppUpdate.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(AppUpdate.isNewer("0.1", than: "0.1.0"))
    }
}
