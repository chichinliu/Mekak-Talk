import XCTest
@testable import TalkCore

final class CLIExecutableDiscoveryTests: XCTestCase {
    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cli-discovery-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    private func executable(_ path: URL, permissions: Int = 0o755) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path.path)
    }

    func testDiscoveryIncludesSpeechToolsAndCustomWrapperButExcludesUnrelatedPrograms() throws {
        let directory = try fixture()
        try executable(directory.appendingPathComponent("whisper-cli"))
        try executable(directory.appendingPathComponent("parakeet-cli"))
        try executable(directory.appendingPathComponent("asr"))
        let wrapper = directory.appendingPathComponent("my-voice-tool")
        try executable(wrapper)
        let choices = CLIExecutableDiscovery.speechTools(in: [directory.path], including: wrapper.path)
        XCTAssertEqual(choices.map(\.name), ["my-voice-tool", "whisper-cli", "parakeet-cli"])
    }

    func testDiscoveryRejectsDirectoriesAndNonExecutableFiles() throws {
        let directory = try fixture()
        let folder = directory.appendingPathComponent("whisper-cli")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try executable(directory.appendingPathComponent("parakeet-cli"), permissions: 0o644)
        XCTAssertFalse(CLIExecutableDiscovery.isExecutable(folder.path))
        XCTAssertTrue(CLIExecutableDiscovery.speechTools(in: [directory.path]).isEmpty)
        XCTAssertFalse(CLIExecutableDiscovery.isExecutable("whisper-cli"))
        XCTAssertFalse(CLIExecutableDiscovery.isExecutable(directory.appendingPathComponent("missing").path))
    }

    func testDiscoveryKeepsStableSymlinkAndDeduplicatesRepeatedDirectories() throws {
        let directory = try fixture()
        let binary = directory.appendingPathComponent("recognizer-v1")
        try executable(binary)
        let symlink = directory.appendingPathComponent("whisper-cli")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: binary)
        XCTAssertTrue(CLIExecutableDiscovery.isExecutable(symlink.path))
        let choices = CLIExecutableDiscovery.speechTools(in: [directory.path, directory.appendingPathComponent(".").path], including: symlink.path)
        XCTAssertEqual(choices.map(\.path), [symlink.path])
    }

    func testSearchPathsExcludeRelativeAndEmptyEntriesAndIncludeGUIFallbacks() {
        let home = URL(fileURLWithPath: "/Users/fixture")
        let directories = CLIExecutableDiscovery.searchDirectories(environment: ["PATH": ":relative:/custom/bin:/custom/bin/:/opt/homebrew/bin"], home: home)
        XCTAssertEqual(directories.first, "/custom/bin")
        XCTAssertEqual(directories.filter { $0 == "/custom/bin" }.count, 1)
        XCTAssertTrue(directories.contains("/Users/fixture/.local/bin"))
        XCTAssertTrue(directories.contains("/usr/local/bin"))
        XCTAssertFalse(directories.contains("relative"))
    }
}
