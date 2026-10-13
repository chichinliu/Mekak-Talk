import XCTest
@testable import TalkCore

final class DictationStatsTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func record(_ daysAgo: Int, _ text: String, seconds: TimeInterval, to app: String, now: Date) -> DictationRecord {
        DictationRecord(date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, rawText: text, text: text,
                        action: .dictate, backend: .whisper, duration: seconds, destination: app)
    }

    func testSummarizesTodayAndTheLastSevenDays() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12))!
        let history = [
            record(0, "明天開會", seconds: 30, to: "Slack", now: now),
            record(0, "記得帶報告", seconds: 30, to: "Mail", now: now),
            record(2, "Hello world", seconds: 60, to: "Slack", now: now),
            record(9, "太久以前", seconds: 60, to: "Notes", now: now),
        ]
        let stats = DictationStats(history: history, now: now, calendar: calendar)
        XCTAssertEqual(stats.todayCount, 2)
        XCTAssertEqual(stats.todayWords, 9)
        XCTAssertEqual(stats.dailyWords, [0, 0, 0, 0, 2, 0, 9])
        XCTAssertEqual(stats.weekWords, 11)
        XCTAssertEqual(stats.weekMinutes, 2, accuracy: 0.001)
        XCTAssertEqual(stats.wordsPerMinute, 6)
        XCTAssertEqual(stats.topDestinations.map(\.name), ["Slack", "Mail"])
        XCTAssertEqual(stats.topDestinations.first?.count, 2)
    }

    func testEmptyHistoryHasNoSpeed() {
        let stats = DictationStats(history: [], now: Date(), calendar: calendar)
        XCTAssertEqual(stats.dailyWords, Array(repeating: 0, count: 7))
        XCTAssertNil(stats.wordsPerMinute)
        XCTAssertTrue(stats.topDestinations.isEmpty)
    }
}
