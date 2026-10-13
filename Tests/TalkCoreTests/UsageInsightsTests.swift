import XCTest
@testable import TalkCore

final class UsageInsightsTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Taipei")!; return c }
    private func day(_ d: Int, hour: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))! }

    func testLedgerAccumulatesPerDayWithoutText() throws {
        var ledger = UsageLedger()
        ledger.record(words: 40, seconds: 30, at: day(12), calendar: calendar)
        ledger.record(words: 20, seconds: 30, at: day(12, hour: 18), calendar: calendar)
        ledger.record(words: 10, seconds: 6, at: day(13), calendar: calendar)
        XCTAssertEqual(ledger.days.map(\.day), ["2026-10-12", "2026-10-13"])
        XCTAssertEqual(ledger.days.first?.words, 60); XCTAssertEqual(ledger.days.first?.count, 2)
        let json = String(decoding: try JSONEncoder().encode(ledger), as: UTF8.self)
        XCTAssertFalse(json.contains("text"))
    }

    func testSeedsFromExistingHistoryOnce() {
        let history = [DictationRecord(date: day(10), rawText: "", text: "明天開會", action: .dictate, backend: .whisper, duration: 12, destination: "Slack")]
        let ledger = UsageLedger(seedingFrom: history, calendar: calendar)
        XCTAssertEqual(ledger.days.map(\.words), [4])
        XCTAssertEqual(ledger.days.first?.seconds, 12)
    }

    func testTotalsSpeedAndTimeSaved() {
        var ledger = UsageLedger()
        ledger.record(words: 400, seconds: 120, at: day(12), calendar: calendar)
        ledger.record(words: 200, seconds: 60, at: day(13), calendar: calendar)
        let insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.totalWords, 600)
        XCTAssertEqual(insights.totalMinutes, 3, accuracy: 0.001)
        XCTAssertEqual(insights.wordsPerMinute, 200)
        // 600 words typed at 40/min = 15 min, spoken in 3 min.
        XCTAssertEqual(insights.savedMinutes, 12, accuracy: 0.001)
        XCTAssertEqual(insights.todayWords, 200)
        XCTAssertEqual(insights.weekSavedMinutes, 12, accuracy: 0.001)
    }

    func testComparesWithYesterdayAndThePreviousWeek() {
        var ledger = UsageLedger()
        ledger.record(words: 80, seconds: 60, at: day(3), calendar: calendar)
        ledger.record(words: 30, seconds: 6, at: day(12), calendar: calendar)
        ledger.record(words: 50, seconds: 6, at: day(13), calendar: calendar)
        let insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.yesterdayWords, 30)
        XCTAssertEqual(insights.previousWeekSavedMinutes, 1, accuracy: 0.001)
    }

    func testSavedTimeNeverNegative() {
        var ledger = UsageLedger()
        ledger.record(words: 10, seconds: 600, at: day(13), calendar: calendar)
        XCTAssertEqual(UsageInsights(ledger: ledger, typingSpeed: 40, now: day(13), calendar: calendar).savedMinutes, 0)
    }

    func testActiveDaysAndStreaks() {
        var ledger = UsageLedger()
        for d in [1, 2, 3, 5, 6, 12, 13] { ledger.record(words: 1, seconds: 1, at: day(d), calendar: calendar) }
        var insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.activeDays, 7)
        XCTAssertEqual(insights.currentStreak, 2)
        XCTAssertEqual(insights.longestStreak, 3)
        // A streak survives until the end of the next day.
        insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(14), calendar: calendar)
        XCTAssertEqual(insights.currentStreak, 2)
        insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(15), calendar: calendar)
        XCTAssertEqual(insights.currentStreak, 0)
    }

    func testDailyWordsForHeatmapEndsToday() {
        var ledger = UsageLedger()
        ledger.record(words: 5, seconds: 1, at: day(11), calendar: calendar)
        ledger.record(words: 9, seconds: 1, at: day(13), calendar: calendar)
        let insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.dailyWords(days: 4), [0, 5, 0, 9])
    }

    func testTypingSpeedDefaultsToFortyAndOldSettingsDecode() throws {
        XCTAssertEqual(TalkSettings().typingWordsPerMinute, 40)
        let decoded = try JSONDecoder().decode(TalkSettings.self, from: JSONEncoder().encode(TalkSettings()))
        XCTAssertEqual(decoded.typingWordsPerMinute, 40)
    }
}

final class UsageBreakdownTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Taipei")!; return c }
    private func day(_ d: Int, hour: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))! }

    private func ledger() -> UsageLedger {
        var ledger = UsageLedger()
        ledger.record(words: 100, seconds: 30, at: day(13, hour: 9), app: "Slack", action: .dictate, calendar: calendar)
        ledger.record(words: 40, seconds: 20, at: day(13, hour: 9), app: "Mail", action: .translate, calendar: calendar)
        ledger.record(words: 60, seconds: 90, at: day(12, hour: 21), app: "Slack", action: .dictate, calendar: calendar)
        ledger.record(words: 300, seconds: 120, at: day(1, hour: 10), app: "Notes", action: .ask, calendar: calendar)
        return ledger
    }

    func testBreaksDownByHourAppAndAction() {
        let insights = UsageInsights(ledger: ledger(), typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.hourCounts[9], 2); XCTAssertEqual(insights.hourCounts[21], 1)
        XCTAssertEqual(insights.peakHour, 9)
        XCTAssertEqual(insights.apps.map(\.name), ["Slack", "Notes", "Mail"])
        XCTAssertEqual(insights.apps.first?.count, 2); XCTAssertEqual(insights.apps.first?.words, 160)
        XCTAssertEqual(insights.actionCounts[.dictate], 2); XCTAssertEqual(insights.actionCounts[.ask], 1)
    }

    func testPersonalBests() {
        let insights = UsageInsights(ledger: ledger(), typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.bestDay?.words, 300)
        XCTAssertEqual(insights.longestSession, 120)
    }

    func testWeeklyWordsAndSpeedEndWithThisWeek() {
        let insights = UsageInsights(ledger: ledger(), typingSpeed: 40, now: day(13), calendar: calendar)
        let weeks = insights.weekly(weeks: 3)
        XCTAssertEqual(weeks.count, 3)
        XCTAssertEqual(weeks.last?.words, 200)          // Oct 7 to 13
        XCTAssertEqual(weeks[1].words, 300)             // Sep 30 to Oct 6
        XCTAssertEqual(weeks[0].words, 0)
        XCTAssertEqual(weeks.last?.wordsPerMinute, 86)  // 200 words over 140 s
    }

    func testBackfillAddsBreakdownWithoutCountingWordsTwice() throws {
        let json = #"{"days":[{"day":"2026-10-13","words":4,"seconds":12,"count":1}]}"#
        var ledger = try JSONDecoder().decode(UsageLedger.self, from: Data(json.utf8))
        let history = [DictationRecord(date: day(13, hour: 8), rawText: "", text: "明天開會", action: .dictate, backend: .whisper, duration: 12, destination: "Slack")]
        ledger.backfillBreakdown(from: history, calendar: calendar)
        ledger.backfillBreakdown(from: history, calendar: calendar)
        let insights = UsageInsights(ledger: ledger, typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.totalWords, 4)
        XCTAssertEqual(insights.peakHour, 8)
        XCTAssertEqual(insights.apps.first?.count, 1)
    }

    func testOldLedgerWithoutBreakdownStillDecodes() throws {
        let json = #"{"days":[{"day":"2026-10-12","words":5,"seconds":3,"count":1}]}"#
        let decoded = try JSONDecoder().decode(UsageLedger.self, from: Data(json.utf8))
        let insights = UsageInsights(ledger: decoded, typingSpeed: 40, now: day(13), calendar: calendar)
        XCTAssertEqual(insights.totalWords, 5)
        XCTAssertTrue(insights.apps.isEmpty)
        XCTAssertNil(insights.peakHour)
    }
}
