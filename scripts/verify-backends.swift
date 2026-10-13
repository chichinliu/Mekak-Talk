import Foundation

/// Compile with TalkCore sources to exercise the same backend adapters as the app.
/// Usage: verify-backends <whisper-cli> <model.bin> <sample.wav> [ollama] [model-name]
@main
struct VerifyBackends {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 4 else { throw TalkError("Usage: verify-backends <whisper-cli> <model.bin> <sample.wav> [ollama] [model-name]") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("HydayTalkVerification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("sample with spaces.wav")
        try await SpeechTranscription.normalize(source: URL(fileURLWithPath: arguments[3]), output: file)
        var settings = TalkSettings(); settings.speechBackend = .whisper; settings.locale = "en-US"
        settings.whisperExecutable = arguments[1]; settings.whisperModel = arguments[2]
        let transcript = try await SpeechTranscription.transcribe(file: file, settings: settings)
        guard transcript.lowercased().contains("country") else { throw TalkError("Whisper sample transcript did not contain the expected word.") }
        print("PASS: real whisper.cpp inference, \(transcript.count) transcript characters")
        settings.speechBackend = .cli; settings.speechCLIExecutable = arguments[1]
        // Replace the fixed model argument before the adapter expands recording placeholders.
        settings.speechCLIArguments = "-m '\(arguments[2].replacingOccurrences(of: "'", with: "'\\''"))' -f {audio} -l {language} -nt -np"
        let cliTranscript = try await SpeechTranscription.transcribe(file: file, settings: settings)
        guard cliTranscript.lowercased().contains("country") else { throw TalkError("CLI transcription did not contain the expected word.") }
        print("PASS: real custom CLI speech adapter")
        if arguments.count >= 6 {
            let output = try await ProcessRunner.run(executable: arguments[4], arguments: ["run", arguments[5]],
                input: "請只輸出「測試完成」四個繁體中文字，不要輸出任何其他內容。", timeout: 120)
            guard output.contains("測試完成") else { throw TalkError("Local text model did not return the expected response.") }
            print("PASS: real local text CLI via stdin")
        }
    }
}
