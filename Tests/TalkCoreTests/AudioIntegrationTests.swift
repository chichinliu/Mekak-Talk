import XCTest
import AVFoundation
@testable import TalkCore

final class AudioIntegrationTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("Hyday Talk Test " + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testAudioNormalizationProducesWhisperCompatiblePCM() async throws {
        let source = folder.appendingPathComponent("录音 with spaces.caf")
        let output = folder.appendingPathComponent("normalized.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        for channel in 0..<2 { for frame in 0..<4410 { buffer.floatChannelData![channel][frame] = 0 } }
        var fileSettings = format.settings; fileSettings.removeValue(forKey: AVLinearPCMIsNonInterleaved)
        do { let file = try AVAudioFile(forWriting: source, settings: fileSettings); try file.write(from: buffer) }
        try await SpeechTranscription.normalize(source: source, output: output)
        let audio = try AVAudioFile(forReading: output)
        XCTAssertEqual(audio.fileFormat.sampleRate, 16000)
        XCTAssertEqual(audio.fileFormat.channelCount, 1)
        XCTAssertEqual(audio.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertEqual(audio.fileFormat.settings[AVLinearPCMIsFloatKey] as? Bool, false)
        XCTAssertGreaterThan(audio.length, 1000)
    }

    func testLocalWhisperInvocationAndTextOutput() async throws {
        let executable = folder.appendingPathComponent("mock whisper-cli")
        let model = folder.appendingPathComponent("模型 ggml.bin")
        let audio = folder.appendingPathComponent("audio file.wav")
        let script = """
        #!/bin/sh
        output=''
        lang=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -of) output="$2"; shift 2 ;;
            -l) lang="$2"; shift 2 ;;
            -m|-f) test -f "$2" || exit 4; shift 2 ;;
            *) shift ;;
          esac
        done
        test "$lang" = 'zh' || exit 5
        printf '這是本機辨識結果。\\n' > "${output}.txt"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try Data("fixture".utf8).write(to: model); try Data("fixture".utf8).write(to: audio)
        var settings = TalkSettings(); settings.speechBackend = .whisper
        settings.whisperExecutable = executable.path; settings.whisperModel = model.path
        let text = try await SpeechTranscription.transcribe(file: audio, settings: settings)
        XCTAssertEqual(text, "這是本機辨識結果。")
    }
    func testCustomCLIReceivesAudioPathAsSingleArgument() async throws {
        let executable = folder.appendingPathComponent("mock stt")
        let audio = folder.appendingPathComponent("path with spaces.wav")
        try Data("fixture".utf8).write(to: audio)
        let script = """
        #!/bin/sh
        test "$#" = 2 || exit 3
        test -f "$1" || exit 4
        test "$2" = 'zh' || exit 5
        printf 'CLI 辨識結果'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var settings = TalkSettings(); settings.speechBackend = .cli
        settings.speechCLIExecutable = executable.path; settings.speechCLIArguments = "{audio} {language}"
        let text = try await SpeechTranscription.transcribe(file: audio, settings: settings)
        XCTAssertEqual(text, "CLI 辨識結果")
    }

    func testWhisperCLIMissingModelFailsBeforeLaunchingTool() async throws {
        let executable = folder.appendingPathComponent("whisper-cli")
        let launched = folder.appendingPathComponent("launched")
        let audio = folder.appendingPathComponent("audio.wav")
        let script = """
        #!/bin/sh
        printf started > '\(launched.path)'
        exit 3
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try Data("fixture".utf8).write(to: audio)
        var settings = TalkSettings(); settings.speechBackend = .cli
        settings.speechCLIExecutable = executable.path; settings.speechCLIArguments = "{audio}"
        do {
            _ = try await SpeechTranscription.transcribe(file: audio, settings: settings)
            XCTFail("Missing Whisper model must fail validation")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("尚未指定模型"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: launched.path), "Incomplete Whisper settings must not launch the CLI")
    }

    func testCLIDecorativeOutputIsNotDictation() async throws {
        let executable = folder.appendingPathComponent("mock stt")
        try "#!/bin/sh\nprintf '────────────────────────────────────\\n'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        var settings = TalkSettings(); settings.speechBackend = .cli
        settings.speechCLIExecutable = executable.path; settings.speechCLIArguments = "{audio}"
        do {
            _ = try await SpeechTranscription.transcribe(file: folder.appendingPathComponent("audio.wav"), settings: settings)
            XCTFail("A separator must not be inserted as recognized speech")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("未辨識到文字"), error.localizedDescription)
        }
    }
}
