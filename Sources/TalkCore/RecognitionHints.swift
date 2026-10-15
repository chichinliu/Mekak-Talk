import Foundation

public enum RecognitionHints {
    /// Manual entries first, then learned ones newest first.
    public static func ordered(_ dictionary: [DictionaryEntry]) -> [DictionaryEntry] {
        dictionary.filter { !$0.isAutomatic } + dictionary.filter(\.isAutomatic).reversed()
    }

    /// Manual terms first, then learned terms newest first, up to the limit.
    public static func terms(dictionary: [DictionaryEntry], limit: Int = 100) -> [String] {
        var result: [String] = []
        for entry in ordered(dictionary) where result.count < limit && !entry.term.isEmpty && !result.contains(entry.term) {
            result.append(entry.term)
        }
        return result
    }

    /// Recognition models sometimes answer a short clip by reciting the hint list they were given.
    /// A transcript made mostly of five or more hint terms is that list, not speech.
    public static func isEcho(_ transcript: String, hints: [String]) -> Bool {
        var known = Set<String>()
        for hint in hints {
            known.insert(hint.lowercased())
            if let last = hint.split(separator: "/").last { known.insert(last.lowercased()) }
        }
        let words = transcript.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "、，,"))).filter { !$0.isEmpty }
        let matched = words.filter { word in
            known.contains(word.lowercased()) || word.split(separator: "/").last.map { known.contains($0.lowercased()) } == true
        }.count
        return matched >= 5 && matched * 10 >= words.count * 7
    }
}
