import Foundation

/// One day of dictation usage. Holds only counts, never what was said.
public struct DailyUsage: Codable, Equatable, Sendable {
    public var day: String
    public var words: Int
    public var seconds: Double
    public var count: Int
}

public struct AppTally: Codable, Equatable, Sendable {
    public var count: Int
    public var words: Int
}

/// Long-term usage kept apart from history, so clearing or disabling history keeps the figures.
public struct UsageLedger: Codable, Equatable, Sendable {
    public private(set) var days: [DailyUsage] = []
    // Optional so ledgers saved before these breakdowns existed still decode.
    private(set) var hours: [Int]?
    private(set) var apps: [String: AppTally]?
    private(set) var actions: [String: Int]?
    private(set) var longestSeconds: Double?
    public init() {}

    public init(seedingFrom history: [DictationRecord], calendar: Calendar = .current) {
        for item in history.sorted(by: { $0.date < $1.date }) {
            record(words: TextProcessing.wordCount(item.text), seconds: item.duration, at: item.date,
                   app: item.destination, action: item.action, calendar: calendar)
        }
    }

    /// Ledgers saved before hours, apps and actions were tracked get them from history once; day totals stay as they are.
    public mutating func backfillBreakdown(from history: [DictationRecord], calendar: Calendar = .current) {
        guard hours == nil else { return }
        var source = UsageLedger(seedingFrom: history, calendar: calendar)
        if source.hours == nil { source.hours = Array(repeating: 0, count: 24) }
        hours = source.hours; apps = source.apps; actions = source.actions; longestSeconds = source.longestSeconds
    }

    public mutating func record(words: Int, seconds: Double, at date: Date = Date(), app: String? = nil,
                                action: VoiceAction? = nil, calendar: Calendar = .current) {
        var hourly = hours ?? Array(repeating: 0, count: 24)
        hourly[calendar.component(.hour, from: date)] += 1; hours = hourly
        if let app, !app.isEmpty {
            var tally = apps?[app] ?? AppTally(count: 0, words: 0)
            tally.count += 1; tally.words += words
            apps = (apps ?? [:]).merging([app: tally]) { $1 }
        }
        if let action { actions = (actions ?? [:]).merging([action.rawValue: 1], uniquingKeysWith: +) }
        longestSeconds = max(longestSeconds ?? 0, seconds)
        let key = Self.key(for: date, calendar: calendar)
        if let index = days.firstIndex(where: { $0.day == key }) {
            days[index].words += words; days[index].seconds += seconds; days[index].count += 1
        } else {
            days.append(DailyUsage(day: key, words: words, seconds: seconds, count: 1))
            days.sort { $0.day < $1.day }
        }
    }

    static func key(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

public struct WeekUsage: Equatable, Sendable {
    public let start: Date
    public let words: Int
    public let seconds: Double
    public var wordsPerMinute: Int? { seconds > 0 ? Int((Double(words) / (seconds / 60)).rounded()) : nil }
}

public struct AppUsage: Equatable, Sendable {
    public let name: String
    public let count: Int
    public let words: Int
}

public struct UsageInsights: Sendable {
    public let hourCounts: [Int]
    public let apps: [AppUsage]
    public let actionCounts: [VoiceAction: Int]
    public let bestDay: DailyUsage?
    public let longestSession: Double
    private let days: [DailyUsage]
    /// The hour with the most dictations, or nil before any were recorded by hour.
    public var peakHour: Int? {
        guard let peak = hourCounts.max(), peak > 0 else { return nil }
        return hourCounts.firstIndex(of: peak)
    }
    public let totalWords: Int
    public let totalMinutes: Double
    public let savedMinutes: Double
    public let todayWords: Int
    public let weekSavedMinutes: Double
    public let yesterdayWords: Int
    /// Days 8 to 14 before today, for comparing with `weekSavedMinutes`.
    public let previousWeekSavedMinutes: Double
    public let activeDays: Int
    public let currentStreak: Int
    public let longestStreak: Int
    private let wordsByDay: [String: Int]
    private let now: Date
    private let calendar: Calendar

    public var wordsPerMinute: Int? { totalMinutes > 0 ? Int((Double(totalWords) / totalMinutes).rounded()) : nil }

    /// Time saved estimates typing the same words at `typingSpeed` words per minute, minus the time spent speaking.
    public init(ledger: UsageLedger, typingSpeed: Int, now: Date = Date(), calendar: Calendar = .current) {
        self.now = now; self.calendar = calendar
        self.days = ledger.days
        hourCounts = ledger.hours ?? Array(repeating: 0, count: 24)
        apps = (ledger.apps ?? [:]).map { AppUsage(name: $0.key, count: $0.value.count, words: $0.value.words) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : ($0.words != $1.words ? $0.words > $1.words : $0.name < $1.name) }
        actionCounts = Dictionary(uniqueKeysWithValues: (ledger.actions ?? [:]).compactMap { key, value in
            VoiceAction(rawValue: key).map { ($0, value) }
        })
        bestDay = ledger.days.max { $0.words < $1.words }
        longestSession = ledger.longestSeconds ?? 0
        let speed = Double(max(1, typingSpeed))
        func saved(_ days: [DailyUsage]) -> Double {
            max(0, Double(days.reduce(0) { $0 + $1.words }) / speed - days.reduce(0) { $0 + $1.seconds } / 60)
        }
        let days = ledger.days
        totalWords = days.reduce(0) { $0 + $1.words }
        totalMinutes = days.reduce(0) { $0 + $1.seconds } / 60
        savedMinutes = saved(days)
        wordsByDay = Dictionary(days.map { ($0.day, $0.words) }, uniquingKeysWith: +)
        let today = calendar.startOfDay(for: now)
        let weekKeys = Set((0..<7).map { UsageLedger.key(for: calendar.date(byAdding: .day, value: -$0, to: today)!, calendar: calendar) })
        weekSavedMinutes = saved(days.filter { weekKeys.contains($0.day) })
        let previousKeys = Set((7..<14).map { UsageLedger.key(for: calendar.date(byAdding: .day, value: -$0, to: today)!, calendar: calendar) })
        previousWeekSavedMinutes = saved(days.filter { previousKeys.contains($0.day) })
        yesterdayWords = wordsByDay[UsageLedger.key(for: calendar.date(byAdding: .day, value: -1, to: today)!, calendar: calendar)] ?? 0
        todayWords = wordsByDay[UsageLedger.key(for: today, calendar: calendar)] ?? 0
        let active = days.filter { $0.count > 0 }.map(\.day)
        activeDays = Set(active).count
        // Consecutive calendar days, measured on day keys converted back to dates.
        let dates = Set(active).compactMap { key -> Date? in
            let p = key.split(separator: "-").compactMap { Int($0) }
            return p.count == 3 ? calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
        }.map { calendar.startOfDay(for: $0) }.sorted()
        var longest = 0, run = 0, previous: Date?
        for date in dates {
            run = previous.flatMap { calendar.dateComponents([.day], from: $0, to: date).day } == 1 ? run + 1 : 1
            longest = max(longest, run); previous = date
        }
        longestStreak = longest
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        if let last = dates.last, last == today || last == yesterday { currentStreak = run } else { currentStreak = 0 }
    }

    /// Rolling seven-day windows, oldest first; the last one ends today.
    public func weekly(weeks: Int) -> [WeekUsage] {
        let today = calendar.startOfDay(for: now)
        return (0..<weeks).reversed().map { offset in
            let start = calendar.date(byAdding: .day, value: -(offset * 7 + 6), to: today)!
            let keys = Set((0..<7).map { UsageLedger.key(for: calendar.date(byAdding: .day, value: $0, to: start)!, calendar: calendar) })
            let window = days.filter { keys.contains($0.day) }
            return WeekUsage(start: start, words: window.reduce(0) { $0 + $1.words }, seconds: window.reduce(0) { $0 + $1.seconds })
        }
    }

    /// Words per day, oldest first, ending today.
    public func dailyWords(days: Int) -> [Int] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { offset in
            wordsByDay[UsageLedger.key(for: calendar.date(byAdding: .day, value: -offset, to: today)!, calendar: calendar)] ?? 0
        }
    }
}
