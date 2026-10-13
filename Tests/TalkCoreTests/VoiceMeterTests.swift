import XCTest
@testable import TalkCore

final class VoiceMeterTests: XCTestCase {
    func testRoomNoiseStaysFlat() {
        XCTAssertEqual(VoiceMeter.display(level: 0.1), 0)
        XCTAssertEqual(VoiceMeter.display(level: 0.28), 0)
    }

    func testSpeechSpreadsAcrossTheMeter() {
        let soft = VoiceMeter.display(level: 0.45), normal = VoiceMeter.display(level: 0.6), loud = VoiceMeter.display(level: 0.8)
        XCTAssertLessThan(soft, 0.4)
        XCTAssertGreaterThan(loud, 0.9)
        XCTAssertGreaterThan(loud - soft, 0.6)
        XCTAssertTrue(soft < normal && normal < loud)
    }

    func testJitterVariesNeighbouringBarsButStaysBounded() {
        let values = (0..<20).map { VoiceMeter.jitter(sample: $0) }
        XCTAssertGreaterThan(Set(values.map { ($0 * 100).rounded() }).count, 5)
        XCTAssertTrue(values.allSatisfy { $0 >= 0.6 && $0 <= 1.15 })
        XCTAssertEqual(VoiceMeter.jitter(sample: 7), VoiceMeter.jitter(sample: 7))
    }
}
