import Foundation
import CryptoKit

public struct LocalSpeechModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let filename: String
    public let bytes: Int64
    public let sha256: String
    public var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }
    public var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    public static let recommended = LocalSpeechModel(id: "large-v3-turbo-q5_0", title: "Whisper Large v3 Turbo",
        detail: "建議使用，支援中文與多語辨識。", filename: "ggml-large-v3-turbo-q5_0.bin", bytes: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2")
    public static let small = LocalSpeechModel(id: "small", title: "Whisper Small",
        detail: "較小的多語模型，適合減少儲存空間。", filename: "ggml-small.bin", bytes: 487_601_967,
        sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b")
    public static let all: [LocalSpeechModel] = [recommended, small]

    public init(id: String, title: String, detail: String, filename: String, bytes: Int64, sha256: String) {
        self.id = id; self.title = title; self.detail = detail; self.filename = filename
        self.bytes = bytes; self.sha256 = sha256
    }
}

public enum LocalModelInstaller {
    public static func validate(source: URL, model: LocalSpeechModel) async throws {
        let worker = Task.detached(priority: .utility) { try verify(source: source, model: model, output: nil) }
        try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    /// Stream the model into a private staging file, verifying it before an
    /// atomic replacement. Cancellation or corrupt downloads preserve the old model.
    public static func install(source: URL, model: LocalSpeechModel, directory: URL) async throws -> URL {
        let worker = Task.detached(priority: .utility) { try installFile(source: source, model: model, directory: directory) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    private static func installFile(source: URL, model: LocalSpeechModel, directory: URL) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent(model.filename)
        let staging = directory.appendingPathComponent(".download-" + UUID().uuidString)
        guard manager.createFile(atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw TalkError("無法儲存模型，請確認磁碟空間後重試。")
        }
        defer { try? manager.removeItem(at: staging) }
        let output = try FileHandle(forWritingTo: staging)
        defer { try? output.close() }
        try verify(source: source, model: model, output: output)
        try output.synchronize(); try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw TalkError("無法儲存模型，請確認磁碟空間後重試。") }
        return destination
    }

    private static func verify(source: URL, model: LocalSpeechModel, output: FileHandle?) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hash = SHA256(); var count: Int64 = 0
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            count += Int64(data.count)
            guard count <= model.bytes else { throw TalkError("模型檔案驗證失敗，請重新下載。") }
            hash.update(data: data); try output?.write(contentsOf: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == model.bytes, digest == model.sha256 else { throw TalkError("模型檔案驗證失敗，請重新下載。") }
        try Task.checkCancellation()
    }
}

public enum LocalSpeechConfiguration {
    /// Keep legacy settings decodable; CLI fields remain stored for rollback.
    public static func migrate(_ settings: inout TalkSettings, engine: String) {
        if settings.speechBackend == .cli {
            if SpeechCLIConfiguration.isWhisper(settings.speechCLIExecutable),
               let model = SpeechCLIConfiguration.whisperModelPath(arguments: settings.speechCLIArguments),
               SpeechCLIConfiguration.isReadableModel(model) { settings.whisperModel = model }
            settings.speechBackend = .whisper
        }
        if CLIExecutableDiscovery.isExecutable(engine) { settings.whisperExecutable = engine }
    }
}
