import Foundation

/// Usage figures for the overview, computed from the local dictation history.
public struct DictationStats: Equatable, Sendable {
    public struct Destination: Equatable, Sendable {
        public let name: String
        public let count: Int
    }

    public let todayCount: Int
    public let todayWords: Int
    /// Oldest first; the last value is today.
    public let dailyWords: [Int]
    public let weekWords: Int
    public let weekMinutes: Double
    public let topDestinations: [Destination]

    public var wordsPerMinute: Int? { weekMinutes > 0 ? Int((Double(weekWords) / weekMinutes).rounded()) : nil }

    public init(history: [DictationRecord], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).map { calendar.date(byAdding: .day, value: $0 - 6, to: today)! }
        let week = history.filter { $0.date >= days[0] && $0.date < calendar.date(byAdding: .day, value: 1, to: today)! }
        let words = { (records: [DictationRecord]) in records.reduce(0) { $0 + TextProcessing.wordCount($1.text) } }
        dailyWords = days.map { day in words(week.filter { calendar.isDate($0.date, inSameDayAs: day) }) }
        let todays = week.filter { calendar.isDate($0.date, inSameDayAs: today) }
        todayCount = todays.count
        todayWords = words(todays)
        weekWords = words(week)
        weekMinutes = week.reduce(0) { $0 + $1.duration } / 60
        let counts = Dictionary(grouping: week, by: \.destination).mapValues(\.count)
        topDestinations = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map { Destination(name: $0.key, count: $0.value) }
    }
}
