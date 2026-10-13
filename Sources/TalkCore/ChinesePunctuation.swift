import Foundation

/// Formats Chinese sentences without changing numeric or technical notation.
enum ChinesePunctuation {
    private static let technical = try! NSRegularExpression(pattern: #"```[\s\S]*?```|`[^`\n]+`|(?i:https?://|www\.)[^\s\p{Han}，。！？；：（）「」『』<>"'`]+|[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}|\b[vV]?\d+(?:[.,:]\d+)+|\b[A-Za-z_][A-Za-z0-9_\-]*(?:\.[A-Za-z0-9_\-]+)+"#)
    private static let punctuation: [Character: Character] = [
        ",": "，", ".": "。", "!": "！", "?": "？", ":": "：", ";": "；",
        "(": "（", ")": "）", "[": "［", "]": "］"
    ]

    static func normalize(_ text: String) -> String {
        let characters = Array(text)
        guard characters.contains(where: isHan) else { return text }
        let indices = Array(text.indices)
        let offsets = Dictionary(uniqueKeysWithValues: indices.enumerated().map { ($0.element, $0.offset) })
        var protected = Array(repeating: false, count: characters.count)
        for match in technical.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let start = offsets[range.lowerBound] else { continue }
            var end = offsets[range.upperBound] ?? characters.count
            // A sentence-ending comma/period is not part of the preceding URL.
            if text[range].lowercased().hasPrefix("http") || text[range].lowercased().hasPrefix("www.") {
                while end > start && ".,!?;:)]".contains(characters[end - 1]) { end -= 1 }
            }
            for index in start..<end { protected[index] = true }
        }
        for index in characters.indices where index > 0 && index + 1 < characters.count {
            if ",.:".contains(characters[index]), characters[index - 1].isNumber, characters[index + 1].isNumber {
                protected[index] = true
            }
        }

        var quotes: [(start: Int, end: Int, single: Bool)] = []
        var opening: [Character: Int] = [:]
        for index in characters.indices where !protected[index] {
            let character = characters[index]
            if character.isNewline { opening.removeAll(); continue }
            guard character == "\"" || character == "'" else { continue }
            // Apostrophes inside Latin words are not quotation marks.
            if character == "'", index > 0, index + 1 < characters.count,
               characters[index - 1].isLetter, characters[index + 1].isLetter { continue }
            if let start = opening.removeValue(forKey: character) {
                quotes.append((start, index, character == "'"))
                if !characters[(start + 1)..<index].contains(where: isHan) {
                    for inner in (start + 1)..<index { protected[inner] = true }
                }
            } else { opening[character] = index }
        }

        var chinese = Array(repeating: false, count: characters.count)
        var quoted = Array(repeating: false, count: characters.count)
        for quote in quotes { for offset in (quote.start + 1)..<quote.end { quoted[offset] = true } }
        var start = 0
        for index in characters.indices {
            let endsSentence = characters[index].isNewline
                || (!protected[index] && !quoted[index] && ".!?。！？".contains(characters[index]))
            if endsSentence || index == characters.count - 1 {
                let hasChinese = (start...index).contains { !protected[$0] && isHan(characters[$0]) }
                if hasChinese { for offset in start...index { chinese[offset] = true } }
                start = index + 1
            }
        }

        var output = characters
        for index in characters.indices where chinese[index] && !protected[index] {
            if let replacement = punctuation[characters[index]] { output[index] = replacement }
        }
        for quote in quotes where chinese[quote.start] || chinese[quote.end] {
            output[quote.start] = quote.single ? "『" : "「"
            output[quote.end] = quote.single ? "』" : "」"
        }
        // Remove ASR-added spaces at Chinese punctuation boundaries; keep
        // English word spacing, line breaks, and numeric/code token contents.
        var result = ""
        var index = 0
        while index < output.count {
            result.append(output[index])
            var next = index + 1
            if !protected[index] && "，。！？；：）］」』".contains(output[index]) {
                while next < output.count && (output[next] == " " || output[next] == "\t") { next += 1 }
                if next < output.count && (isHan(output[next]) || "（［「『".contains(output[next])) {
                    index = next; continue
                }
            }
            index += 1
        }
        return result
    }

    private static func isHan(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value) || (0x20000...0x323AF).contains($0.value)
        }
    }
}
