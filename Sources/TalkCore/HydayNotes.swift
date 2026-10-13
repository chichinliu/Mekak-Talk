import Foundation

public struct HydayNote: Codable, Equatable, Sendable {
    public var title: String
    /// Relative to the Hyday folder.
    public var path: String
    public var snippet: String
    public init(title: String, path: String, snippet: String) {
        self.title = title; self.path = path; self.snippet = snippet
    }
}

/// Markdown notes the user wrote, skipping Hyday's own index, generated wiki and hidden folders.
enum HydayNoteFiles {
    static let maxFiles = 5000
    static let maxBytes = 1_000_000

    static func list(root: URL) -> [(path: String, text: String)] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [(String, URL)] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                if url.lastPathComponent == "hyday-wiki" { enumerator.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md", (values?.fileSize ?? 0) <= maxBytes else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(base) else { continue }
            files.append((String(full.dropFirst(base.count)), url))
            if files.count >= maxFiles { break }
        }
        return files.sorted { $0.0 < $1.0 }.compactMap { path, url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (path, $0) }
        }
    }

    /// Frontmatter `title`, otherwise the file name.
    static func split(_ text: String, path: String) -> (title: String, body: String) {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (name, text) }
        let title = lines[1..<end].first { $0.hasPrefix("title:") }
            .map { $0.dropFirst(6).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'"))) }
        return (title.flatMap { $0.isEmpty ? nil : $0 } ?? name, lines[(end + 1)...].joined(separator: "\n"))
    }
}

/// Keyword search used when Hyday's own search service is unavailable.
public enum HydayNoteSearch {
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isIdeographic || (0x3040...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
    }

    /// Words split on spaces and punctuation; CJK runs, which have no spaces, become overlapping pairs.
    public static func terms(_ query: String) -> [String] {
        var result: [String] = []
        func add(_ term: String) { if !term.isEmpty, !result.contains(term) { result.append(term) } }
        for word in query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            var run = ""; var runIsCJK = false
            func flush() {
                if runIsCJK {
                    let characters = Array(run)
                    if characters.count == 1 { add(run) }
                    else { for index in 0..<(characters.count - 1) { add(String(characters[index...index + 1])) } }
                } else { add(run) }
                run = ""
            }
            for character in word {
                let cjk = character.unicodeScalars.first.map(isCJK) ?? false
                if !run.isEmpty, cjk != runIsCJK { flush() }
                runIsCJK = cjk; run.append(character)
            }
            if !run.isEmpty { flush() }
        }
        return result
    }

    public static func search(root: URL, query: String, limit: Int = 5) throws -> [HydayNote] {
        let terms = Array(terms(query).prefix(40))
        guard !terms.isEmpty else { return [] }
        var scored: [(score: Int, note: HydayNote)] = []
        for (path, text) in HydayNoteFiles.list(root: root) {
            try Task.checkCancellation()
            let (title, body) = HydayNoteFiles.split(text, path: path)
            let lowered = body.lowercased(); let loweredTitle = title.lowercased()
            var score = 0; var first: String.Index?
            for term in terms {
                let count = min(lowered.components(separatedBy: term).count - 1, 5)
                let inTitle = loweredTitle.contains(term)
                guard count > 0 || inTitle else { continue }
                score += 10 + count + (inTitle ? 5 : 0)
                if let range = lowered.range(of: term), first.map({ range.lowerBound < $0 }) ?? true { first = range.lowerBound }
            }
            guard score > 0 else { continue }
            scored.append((score, HydayNote(title: title, path: path, snippet: snippet(lowered: lowered, body: body, at: first))))
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.note.path < $1.note.path }
            .prefix(limit).map(\.note)
    }

    private static func snippet(lowered: String, body: String, at index: String.Index?) -> String {
        // Lowercasing can change lengths, so map the match back by character offset.
        let offset = index.map { lowered.distance(from: lowered.startIndex, to: $0) } ?? 0
        let characters = Array(body)
        let start = max(0, min(offset, characters.count) - 60)
        let end = min(characters.count, start + 220)
        var text = String(characters[start..<end]).components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        if start > 0 { text = "…" + text }
        if end < characters.count { text += "…" }
        return text
    }
}

/// `@(Name)` entities and `#tags` from the user's notes, used only as recognition hints.
public enum HydayVocabulary {
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?<!\S)(?:@\(([^()\n]+)\)|@\{([^{}\n]+)\}|#(\p{L}[\p{L}\p{N}_/\-]*))"#)

    public static func terms(in text: String) -> [String] {
        var result: [String] = []; var fenced = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
            guard !fenced else { continue }
            let plain = line.replacingOccurrences(of: "`[^`]*`", with: " ", options: .regularExpression)
            for match in pattern.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                for group in 1...3 {
                    guard let range = Range(match.range(at: group), in: plain) else { continue }
                    let term = plain[range].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "/")))
                    if !term.isEmpty, !result.contains(term) { result.append(term) }
                }
            }
        }
        return result
    }

    public static func scan(root: URL, limit: Int = 2000) throws -> [String] {
        var result: [String] = []; var seen = Set<String>()
        for (_, text) in HydayNoteFiles.list(root: root) {
            try Task.checkCancellation()
            for term in terms(in: text) where seen.insert(term).inserted {
                result.append(term)
                if result.count >= limit { return result }
            }
        }
        return result
    }
}

public enum RecognitionHints {
    /// Confirmed dictionary words first, then Hyday vocabulary, without duplicates.
    public static func terms(dictionary: [DictionaryEntry], vocabulary: [String], limit: Int = 100) -> [String] {
        var result: [String] = []
        // Confirmed dictionary words are always hinted; Hyday vocabulary fills the rest up to the limit.
        for term in dictionary.filter({ !$0.isPending }).map(\.replacement) where !term.isEmpty && !result.contains(term) {
            result.append(term)
        }
        for term in vocabulary where result.count < limit && !term.isEmpty && !result.contains(term) {
            result.append(term)
        }
        return result
    }
}
