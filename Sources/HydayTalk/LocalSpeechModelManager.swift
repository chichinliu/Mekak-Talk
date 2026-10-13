import Foundation
import Combine
import TalkCore

@MainActor
final class LocalSpeechModelManager: ObservableObject {
    @Published private(set) var installed: [String: URL] = [:]
    @Published private(set) var busyModelID: String?
    @Published private(set) var status = ""
    @Published private(set) var issue = ""
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var prepared = false
    private let directory = LocalStore().directory.appendingPathComponent("Models", isDirectory: true)

    static var enginePath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/whisper-cli").path }
    var engineReady: Bool { CLIExecutableDiscovery.isExecutable(Self.enginePath) }

    func prepare(currentPath: String, onSelect: @escaping (URL) -> Void) {
        guard !prepared else { return }; prepared = true
        let current = URL(fileURLWithPath: (currentPath as NSString).expandingTildeInPath)
        let legacy = LocalSpeechModel.all.first { $0.filename == current.lastPathComponent }
        generation = UUID(); let run = generation
        busyModelID = legacy?.id ?? LocalSpeechModel.recommended.id; status = "正在驗證模型"
        operation = Task {
            defer { if generation == run { busyModelID = nil; status = ""; operation = nil } }
            do {
                for model in LocalSpeechModel.all {
                    let destination = directory.appendingPathComponent(model.filename)
                    let source = FileManager.default.fileExists(atPath: destination.path) ? destination
                        : (legacy?.id == model.id && SpeechCLIConfiguration.isReadableModel(current.path) ? current : nil)
                    guard let source else { continue }
                    do {
                        let installedURL: URL
                        if source.standardizedFileURL == destination.standardizedFileURL {
                            try await LocalModelInstaller.validate(source: source, model: model); installedURL = destination
                        } else {
                            installedURL = try await LocalModelInstaller.install(source: source, model: model, directory: directory)
                        }
                        try Task.checkCancellation(); guard generation == run else { return }
                        installed[model.id] = installedURL
                    } catch is CancellationError { throw CancellationError() }
                    catch { issue = "模型檔案驗證失敗，請重新下載。" }
                }
                try Task.checkCancellation(); guard generation == run else { return }
                if let selected = legacy.flatMap({ installed[$0.id] }) ?? installed[LocalSpeechModel.recommended.id] {
                    onSelect(selected)
                }
            } catch is CancellationError { }
            catch { issue = "無法準備本機模型，請重新下載。" }
        }
    }

    func download(_ model: LocalSpeechModel, onSelect: @escaping (URL) -> Void) {
        guard busyModelID == nil else { return }
        generation = UUID(); let run = generation
        busyModelID = model.id; status = "正在下載模型"; issue = ""
        operation = Task {
            defer { if generation == run { busyModelID = nil; status = ""; operation = nil } }
            do {
                var request = URLRequest(url: model.downloadURL); request.timeoutInterval = 600
                let (temporary, response) = try await URLSession.shared.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation(); guard generation == run else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TalkError("模型下載失敗，請確認網路後重試。") }
                status = "正在驗證模型"
                let url = try await LocalModelInstaller.install(source: temporary, model: model, directory: directory)
                try Task.checkCancellation(); guard generation == run else { return }
                installed[model.id] = url; onSelect(url)
            } catch is CancellationError { }
            catch { if generation == run { issue = "模型下載或驗證失敗，請確認網路與磁碟空間後重試。" } }
        }
    }

    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil; busyModelID = nil; status = ""
    }
}
