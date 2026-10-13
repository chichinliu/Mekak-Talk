import Foundation

/// Presentation is applied after the model response without guessing new item boundaries.
enum DictationFormatting {
    private static let marker = try! NSRegularExpression(pattern: #"^(?:([1-9][0-9]*)[.)、．][ \t]+|[-*•][ \t]+|第[一二三四五六七八九十](?:項|點)?[，,。．.、：:][ \t]*)"#)

    private static func join(_ lines: [String]) -> String {
        func isHan(_ character: Character?) -> Bool {
            character?.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) } == true
        }
        return lines.reduce("") { result, line in
            guard !result.isEmpty else { return line }
            return result + (isHan(result.last) && isHan(line.first) ? "" : " ") + line
        }
    }

    /// A long reply squeezed into one paragraph is split every two or three sentences.
    static func paragraphs(_ text: String) -> String {
        guard !text.contains("\n"), !text.contains("```"), text.count >= 90 else { return text }
        var sentences: [String] = []; var current = ""
        for character in text {
            current.append(character)
            if "。！？!?".contains(character) { sentences.append(current); current = "" }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { sentences.append(current) }
        guard sentences.count >= 4 else { return text }
        let groups = Int((Double(sentences.count) / 2.5).rounded())
        let size = Int((Double(sentences.count) / Double(max(2, groups))).rounded(.up))
        return stride(from: 0, to: sentences.count, by: size)
            .map { sentences[$0..<min($0 + size, sentences.count)].joined().trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n\n")
    }

    static func apply(_ text: String, layout: DictationLayout) -> String {
        if layout == .automatic { return paragraphs(text) }
        guard !text.contains("```") else { return text }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return text }
        let matches = lines.map { marker.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) }
        // A lone year, measurement or version prefix is not a numbered list.
        let numbers = zip(lines, matches).compactMap { line, match -> Int? in
            guard let match, let range = Range(match.range(at: 1), in: line) else { return nil }
            return Int(line[range])
        }
        let ordered = numbers.isEmpty || numbers == Array(1...numbers.count)
        let first = ordered ? matches.firstIndex(where: { $0 != nil }) : nil
        func content(_ index: Int) -> String {
            guard ordered, let match = matches[index], let range = Range(match.range, in: lines[index]) else { return lines[index] }
            return String(lines[index][range.upperBound...])
        }
        if layout == .paragraph {
            return join(lines.indices.map { content($0) })
        }
        guard let first else { return "1. " + join(lines) }
        var items: [String] = []
        for index in first..<lines.count {
            if matches[index] != nil { items.append(content(index)) }
            else if !items.isEmpty { items[items.count - 1] = join([items[items.count - 1], lines[index]]) }
        }
        let prefix = join(Array(lines[..<first]))
        let list = items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return prefix.isEmpty ? list : prefix + "\n" + list
    }
}
