import AppKit
import AVFoundation
import Speech
import Combine
import TalkCore

@MainActor enum FlowEnvironment { static var isolatedPermissions = true }
enum PermissionKind { case microphone, speech, accessibility }
enum PermissionAuthorization { case notDetermined, denied, restricted, granted }
struct LocalStore {
    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? { nil }
    func save<T: Encodable>(_ value: T, to name: String) throws {}
}
enum KeyStore { static func read(_ account: String) -> String { "" } }
@MainActor final class LocalSpeechModelManager {
    static let enginePath = "/synthetic/whisper-cli"
    let engineReady = true
    func prepare(currentPath: String, onSelect: @escaping (URL) -> Void) {}
    func cancel() {}
}
@MainActor final class AudioCapture {
    static let fixedTranscript = "這是自動複製流程的固定測試文字。"
    static var text = fixedTranscript
    var onTranscript: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: ((Error) -> Void)?
    var usedPartialTranscript = false
    static func cleanAbandonedAudio() {}
    static func requestMicrophone() async -> Bool { true }
    static func requestSpeech() async -> Bool { true }
    func start(settings: TalkSettings) throws {}
    func stop() {}
    func cancel() {}
    func systemTranscript() async -> String { Self.text }
    func audioFile() async throws -> URL { URL(fileURLWithPath: "/synthetic/audio.wav") }
}
@MainActor final class GlobalShortcuts {
    var isBusy: () -> Bool = { false }
    var onAction: ((ShortcutAction) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    func start() {}
    func stop() {}
}
struct InputTarget {
    let name: String
    let selection: String
    let element: AXUIElement?
    let editable: Bool
    let secure: Bool
}
@MainActor enum TextInsertion {
    enum Mode { case success, failure, hold, holdFailure }
    static var mode = Mode.success
    static var capturedTarget: InputTarget?
    static var copied: [String] = []
    static var inserted: [String] = []
    static var continuation: CheckedContinuation<Void, Never>?
    static func reset() {
        mode = .success; capturedTarget = nil
        copied = []; inserted = []; continuation = nil
        AudioCapture.text = AudioCapture.fixedTranscript
    }
    static func startTracking() {}
    static func stopTracking() {}
    static func forgetDestination() {}
    static func capture() -> InputTarget? { capturedTarget }
    static func copy(_ text: String) { copied.append(text) }
    static func insert(_ text: String, target: InputTarget?) async throws -> String {
        guard let target, target.editable, !target.secure, target.element != nil else {
            throw TalkError("文字已保留。請在一般文字輸入框使用，或複製結果。")
        }
        switch mode {
        case .success: break
        case .failure: throw TalkError("輸入位置已變更，文字已保留供複製。")
        case .hold: await withCheckedContinuation { continuation = $0 }
        case .holdFailure:
            await withCheckedContinuation { continuation = $0 }
            throw TalkError("輸入位置已變更，文字已保留供複製。")
        }
        inserted.append(text)
        return "已送出貼上指令至測試編輯器"
    }
}
