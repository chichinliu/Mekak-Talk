import Foundation

public enum SpeechTranscription {
    public static func normalize(source: URL, output: URL) async throws {
        _ = try await ProcessRunner.run(executable: "/usr/bin/afconvert", arguments: ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", source.path, output.path], timeout: 20)
    }

    public static func transcribe(file: URL, settings: TalkSettings, key: String = "", hints: [String]? = nil,
                                  session: URLSession = .shared) async throws -> String {
        let output: String
        switch settings.speechBackend {
        case .system: throw TalkError("系統辨識需從即時音訊串流取得結果。")
        case .whisper:
            let prefix = file.deletingLastPathComponent().appendingPathComponent("transcript").path
            do {
                _ = try await ProcessRunner.run(executable: settings.whisperExecutable,
                    arguments: whisperArguments(settings: settings, file: file, prefix: prefix,
                                                hints: hints ?? settings.activeDictionary.map(\.replacement)), timeout: 180)
            } catch is CancellationError { throw CancellationError() }
            catch { throw TalkError("本機語音辨識未完成，請確認模型已下載後重試。") }
            let url = URL(fileURLWithPath: prefix + ".txt")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw TalkError("本機模型未回傳文字，請重新選擇模型後重試。")
            }
            output = text
        case .cli:
            try SpeechCLIConfiguration.validate(settings)
            let arguments = CLIArguments.expand(try CLIArguments.parse(settings.speechCLIArguments),
                values: ["{audio}": file.path, "{language}": settings.languageCode])
            output = try await ProcessRunner.run(executable: settings.speechCLIExecutable, arguments: arguments, timeout: 180)
        case .api:
            let data = try Data(contentsOf: file)
            guard data.count <= 25_000_000 else { throw TalkError("錄音檔超過上傳大小限制。請縮短錄音。") }
            output = try await APIClient.transcription(audio: data, settings: settings.speechAPI, key: key,
                language: settings.languageCode, dictionary: hints ?? settings.dictionary.map(\.replacement), session: session)
        }
        return try validatedText(output)
    }

    /// Whisper biases toward words in its initial prompt, so dictionary and Hyday terms are
    /// spelled right, and a Traditional Chinese prompt keeps the output in Traditional script.
    public static func whisperArguments(settings: TalkSettings, file: URL, prefix: String, hints: [String]) -> [String] {
        var arguments = ["-m", (settings.whisperModel as NSString).expandingTildeInPath, "-f", file.path,
                         "-l", settings.languageCode, "-otxt", "-of", prefix, "-nt", "-np"]
        let chinese = settings.locale == "zh-TW"
        var terms: [String] = []
        for term in hints where (terms + [term]).joined(separator: "、").count <= 180 { terms.append(term) }
        let prompt = chinese
            ? (terms.isEmpty ? "以下是台灣繁體中文的口語。" : "以下是台灣繁體中文的口語，可能提到：\(terms.joined(separator: "、"))。")
            : (terms.isEmpty ? "" : terms.joined(separator: ", ") + ".")
        if !prompt.isEmpty { arguments += ["--prompt", prompt] }
        return arguments
    }

    public static func validatedText(_ output: String) throws -> String {
        let text = output.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if ["[BLANK_AUDIO]", "[NO_SPEECH]"].contains(trimmed.uppercased()) { return false }
            let scalars = trimmed.unicodeScalars
            // CLI frames and separator-only hallucinations are not speech;
            // retain punctuation within sentences and useful Markdown.
            let boxRule = scalars.count >= 3 && scalars.allSatisfy { (0x2500...0x257F).contains($0.value) }
            let asciiRule = scalars.count >= 8 && scalars.allSatisfy { "-_=*".unicodeScalars.contains($0) }
            return !boxRule && !asciiRule
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TalkError("未辨識到文字，請靠近麥克風後重試。") }
        return text
    }
}
