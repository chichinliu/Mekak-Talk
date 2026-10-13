import XCTest
@testable import TalkCore

final class SpeechCLIConfigurationTests: XCTestCase {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Whisper Setup " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("whisper-cli")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = root.appendingPathComponent("多語 model.bin")
        try Data("fixture-model".utf8).write(to: model)
        return (executable, model)
    }

    func testGeneratedArgumentsPreserveModelPathAndLanguageAndAudioPlaceholders() throws {
        let (executable, model) = try fixture()
        var settings = TalkSettings(); settings.speechBackend = .cli
        settings.speechCLIExecutable = executable.path
        settings.speechCLIArguments = SpeechCLIConfiguration.whisperArguments(modelPath: model.path)
        XCTAssertNoThrow(try SpeechCLIConfiguration.validate(settings))
        let expanded = CLIArguments.expand(try CLIArguments.parse(settings.speechCLIArguments),
            values: ["{audio}": "/audio file.wav", "{language}": settings.languageCode])
        XCTAssertEqual(expanded, ["-m", model.path, "-f", "/audio file.wav", "-l", "zh", "-nt", "-np"])
    }

    func testModelPathQuotingKeepsSpecialCharactersLiteral() throws {
        let path = "/models/a 'quote' \"double\" \\ $HOME $(touch nothing).bin"
        let arguments = SpeechCLIConfiguration.whisperArguments(modelPath: path)
        XCTAssertEqual(SpeechCLIConfiguration.whisperModelPath(arguments: arguments), path)
    }

    func testMissingUnreadableAndDirectoryModelsHaveActionableErrors() throws {
        let (executable, model) = try fixture()
        var settings = TalkSettings(); settings.speechCLIExecutable = executable.path
        for invalid in [model.deletingLastPathComponent().path, model.path + ".missing", "models/relative.bin"] {
            settings.speechCLIArguments = SpeechCLIConfiguration.whisperArguments(modelPath: invalid)
            XCTAssertThrowsError(try SpeechCLIConfiguration.validate(settings)) { error in
                XCTAssertTrue(error.localizedDescription.contains("模型檔無法讀取"))
            }
        }
        settings.speechCLIArguments = "-f {audio} -m"
        XCTAssertThrowsError(try SpeechCLIConfiguration.validate(settings)) { error in
            XCTAssertTrue(error.localizedDescription.contains("尚未指定模型"))
        }
    }

    func testCustomToolsDoNotRequireWhisperSpecificModelFlags() throws {
        let (executable, _) = try fixture()
        let custom = executable.deletingLastPathComponent().appendingPathComponent("custom-stt")
        try FileManager.default.copyItem(at: executable, to: custom)
        var settings = TalkSettings(); settings.speechCLIExecutable = custom.path
        settings.speechCLIArguments = "--audio {audio}"
        XCTAssertNoThrow(try SpeechCLIConfiguration.validate(settings))
        settings.speechCLIArguments = "--language zh"
        XCTAssertThrowsError(try SpeechCLIConfiguration.validate(settings))
    }
}
