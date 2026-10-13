import AppKit
import AVFoundation
import Speech
import Combine
import TalkCore

enum CapturePhase: Equatable {
    case idle, preparing, recording, transcribing, processing, done, failed
    var busy: Bool { [.preparing, .recording, .transcribing, .processing].contains(self) }
    var title: String {
        switch self {
        case .idle: return "等待語音輸入"
        case .preparing: return "正在準備麥克風"
        case .recording: return "正在錄音"
        case .transcribing: return "正在辨識語音"
        case .processing: return "正在整理文字"
        case .done: return "文字處理完成"
        case .failed: return "處理失敗"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published var settings = TalkSettings() {
        didSet {
            guard loaded else { return }
            saveWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.saveSettings() }
            saveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
    @Published private(set) var history: [DictationRecord] = []
    @Published private(set) var phase: CapturePhase = .idle
    @Published private(set) var action: VoiceAction = .dictate
    @Published private(set) var transcript = ""
    @Published private(set) var result = ""
    @Published var notice = ""
    @Published var showPermissionGuide = false
    @Published private(set) var requestingPermission: PermissionKind?
    private(set) var permissionGuideStartStep: PermissionKind?
    @Published private(set) var level = 0.0
    @Published private(set) var elapsed = 0.0
    @Published private(set) var microphoneAllowed = false
    @Published private(set) var speechAllowed = false
    @Published private(set) var accessibilityAllowed = false
    @Published private(set) var shortcutReady = false
    @Published private(set) var destination = ""
    var showWindow: (() -> Void)?
    var onPanelChange: (() -> Void)?
    private let store = LocalStore()
    let localModels = LocalSpeechModelManager()
    private let audio = AudioCapture()
    private let shortcuts = GlobalShortcuts()
    private var loaded = false
    private var saveWork: DispatchWorkItem?
    private var permissionsTimer: Timer?
    private var recordingTimer: Timer?
    private var operation: Task<Void, Never>?
    private var started = Date()
    private var sessionID = UUID()
    private var target: InputTarget?
    private var pendingCorrection: PendingCorrection?
    private var correctionTimer: Timer?
    private var correctionTask: Task<Void, Never>?
    private var sessionSettings = TalkSettings()
    private var sessionHints: [String] = []
    /// Entities and tags from the Hyday folder; only ever used as recognition hints.
    @Published private(set) var hydayVocabulary: [String] = []
    @Published private(set) var scanningHydayVocabulary = false
    private var vocabularyTask: Task<Void, Never>?
    @Published private(set) var usage = UsageLedger()
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        do {
            settings = try store.load(TalkSettings.self, from: "settings.json") ?? TalkSettings()
            settings.dictationLayout = nil // 段落與列表改由自動整理混合排版
        } catch { notice = "無法讀取本機設定，原檔案已備份。請檢查 Application Support/HydayTalk。" }
        do {
            history = try store.load([DictationRecord].self, from: "history.json") ?? []
        } catch { notice += " 無法讀取本機紀錄，原檔案已保留或備份。" }
        if var saved = try? store.load(UsageLedger.self, from: "usage.json") {
            saved.backfillBreakdown(from: history); usage = saved; saveUsage()
        }
        else { usage = UsageLedger(seedingFrom: history); saveUsage() }
        let originalSettings = settings
        LocalSpeechConfiguration.migrate(&settings, engine: LocalSpeechModelManager.enginePath)
        LocalTextConfiguration.migrate(&settings)
        loaded = true
        if settings != originalSettings { saveSettings() }
        audio.onTranscript = { [weak self] text in self?.transcript = text }
        audio.onLevel = { [weak self] level in self?.level = level }
        audio.onFailure = { [weak self] error in
            guard let self, self.phase == .recording else { return }
            self.notice = error.localizedDescription; self.finish()
        }
        shortcuts.isBusy = { [weak self] in self?.phase.busy == true }
        shortcuts.onAvailability = { [weak self] in self?.shortcutReady = $0 }
        shortcuts.onAction = { [weak self] shortcut in
            guard let self else { return }
            switch shortcut {
            case .cancel: self.cancel()
            case .voice(let action):
                if self.phase == .recording { self.finish() }
                else if !self.phase.busy { self.begin(action: action) }
            }
        }
    }

    func start() {
        AudioCapture.cleanAbandonedAudio()
        localModels.prepare(currentPath: settings.whisperModel) { [weak self] url in
            self?.settings.whisperModel = url.path
        }
        TextInsertion.startTracking()
        refreshPermissions()
        reloadHydayVocabulary()
        permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel(); TextInsertion.forgetDestination() }
            })
        }
    }

    func shutdown() {
        localModels.cancel()
        stopWatchingCorrections(); correctionTask?.cancel()
        cancel(); shortcuts.stop(); permissionsTimer?.invalidate(); saveWork?.cancel(); saveSettings()
        TextInsertion.stopTracking()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func refreshPermissions() {
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechAllowed = SFSpeechRecognizer.authorizationStatus() == .authorized
        accessibilityAllowed = AXIsProcessTrusted()
        if accessibilityAllowed { shortcuts.start() } else if shortcutReady { shortcuts.stop() }
    }

    var requiredPermissions: [PermissionKind] {
        settings.speechBackend == .system ? [.microphone, .speech, .accessibility] : [.microphone, .accessibility]
    }
    var completedPermissionCount: Int { requiredPermissions.filter(permissionAllowed).count }
    var permissionsReady: Bool { completedPermissionCount == requiredPermissions.count && shortcutReady }
    func permissionAllowed(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .microphone: return microphoneAllowed
        case .speech: return speechAllowed
        case .accessibility: return accessibilityAllowed
        }
    }
    func authorization(for kind: PermissionKind) -> PermissionAuthorization {
        switch kind {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .restricted
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .granted
            case .denied: return .denied
            case .restricted: return .restricted
            case .notDetermined: return .notDetermined
            @unknown default: return .restricted
            }
        case .accessibility: return accessibilityAllowed ? .granted : .denied
        }
    }
    func openPermissionGuide(at step: PermissionKind? = nil) {
        guard !phase.busy else { return }
        refreshPermissions(); permissionGuideStartStep = step
        UserDefaults.standard.set(true, forKey: "permissionGuideSeen")
        showPermissionGuide = true
    }
    func presentPermissionGuideIfNeeded() {
        refreshPermissions()
        if !permissionsReady && !UserDefaults.standard.bool(forKey: "permissionGuideSeen") { openPermissionGuide() }
    }

    func grantMicrophone() {
        guard requestingPermission == nil else { return }
        requestingPermission = .microphone
        Task {
            defer { requestingPermission = nil }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { _ = await AudioCapture.requestMicrophone() }
            else if !microphoneAllowed { openPrivacy("Microphone") }
            refreshPermissions()
        }
    }
    func grantSpeech() {
        guard requestingPermission == nil else { return }
        requestingPermission = .speech
        Task {
            defer { requestingPermission = nil }
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined { _ = await AudioCapture.requestSpeech() }
            else if !speechAllowed { openPrivacy("SpeechRecognition") }
            refreshPermissions()
        }
    }
    func grantAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
    }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) { NSWorkspace.shared.open(url) }
    }

    /// The folder chosen on the Hyday page, otherwise Hyday's own configured folder.
    var hydayRoot: URL? {
        if let folder = settings.hydayFolder {
            let url = URL(fileURLWithPath: folder)
            return HydayVault.isDirectory(url) ? url : nil
        }
        return HydayVault.configuredRoot()
    }

    func reloadHydayVocabulary() {
        vocabularyTask?.cancel()
        guard let root = hydayRoot else { hydayVocabulary = []; return }
        scanningHydayVocabulary = true
        vocabularyTask = Task {
            let terms = try? await Task.detached(priority: .utility) { try HydayVocabulary.scan(root: root) }.value
            guard !Task.isCancelled else { return }
            hydayVocabulary = terms ?? []; scanningHydayVocabulary = false
        }
    }

    func begin(action: VoiceAction = .dictate) {
        guard !phase.busy else { return }
        if action == .hyday, hydayRoot == nil {
            self.action = action; result = ""
            fail(TalkError("請先在 Hyday 頁設定 Hyday 資料夾。")); return
        }
        refreshPermissions()
        if !microphoneAllowed || (settings.speechBackend == .system && !speechAllowed) {
            openPermissionGuide(at: !microphoneAllowed ? .microphone : .speech)
            showWindow?()
            return
        }
        checkCorrections()
        result = ""
        let snapshot = settings
        do { try validate(snapshot, action: action) }
        catch { fail(error); return }
        target = action == .hyday ? nil : TextInsertion.capture()
        if target?.secure == true { fail(TalkError("這是密碼欄位。請改在一般文字輸入框使用。")); return }
        sessionID = UUID(); let current = sessionID
        sessionSettings = snapshot; self.action = action
        sessionHints = RecognitionHints.terms(dictionary: snapshot.dictionary, vocabulary: hydayVocabulary)
        let hints = sessionHints
        result = ""; transcript = ""; notice = ""; elapsed = 0; level = 0
        destination = action == .hyday ? "Hyday"
            : (snapshot.autoInsert && action != .ask && (target?.editable != true || target?.element == nil)
               ? "剪貼簿" : (target?.name ?? "結果區"))
        phase = .preparing; onPanelChange?()
        operation = Task {
            do {
                var microphone = microphoneAllowed
                if !microphone && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    microphone = await AudioCapture.requestMicrophone()
                }
                guard microphone else { throw TalkError("請允許麥克風存取，再開始錄音。") }
                if snapshot.speechBackend == .system {
                    var speech = speechAllowed
                    if !speech && SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                        speech = await AudioCapture.requestSpeech()
                    }
                    guard speech else { throw TalkError("請允許語音辨識，或改用本機模型、API。") }
                }
                try Task.checkCancellation()
                guard sessionID == current else { return }
                refreshPermissions(); try audio.start(settings: snapshot, hints: hints)
                started = Date(); phase = .recording
                if snapshot.interactionSounds { NSSound(named: "Tink")?.play() }
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.phase == .recording else { return }
                        self.elapsed = Date().timeIntervalSince(self.started)
                        let limit = snapshot.speechBackend == .system ? 55.0 : 180.0
                        if self.elapsed >= limit {
                            self.notice = "已達單次錄音上限（\(Int(limit)) 秒），正在完成辨識。"; self.finish()
                        }
                    }
                }
                onPanelChange?()
            } catch is CancellationError { }
            catch { if sessionID == current { fail(error) } }
        }
    }

    func finish() {
        guard phase == .recording else { return }
        recordingTimer?.invalidate(); recordingTimer = nil
        let spokeAt = Date()
        elapsed = spokeAt.timeIntervalSince(started); audio.stop(); level = 0
        let duration = elapsed; let current = sessionID; let snapshot = sessionSettings
        let voiceAction = action; let inputTarget = target; let hints = sessionHints
        phase = .transcribing; onPanelChange?()
        if snapshot.interactionSounds { NSSound(named: "Pop")?.play() }
        operation = Task {
            defer { if sessionID == current { audio.cancel() } }
            do {
                let raw: String
                if snapshot.speechBackend == .system {
                    raw = try SpeechTranscription.validatedText(await audio.systemTranscript())
                    if audio.usedPartialTranscript { notice = "系統未回傳完整結果，這次保留最後的辨識文字。" }
                }
                else {
                    let file = try await audio.audioFile()
                    raw = try await SpeechTranscription.transcribe(file: file, settings: snapshot,
                        key: snapshot.speechBackend == .api ? KeyStore.read("speech") : "", hints: hints)
                }
                try Task.checkCancellation(); guard sessionID == current else { return }
                guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TalkError("沒有辨識到文字，請再試一次。") }
                transcript = raw
                let cleaned = TextProcessing.clean(raw, settings: snapshot)
                var output = cleaned
                var aiFormatted = false
                if snapshot.requiresTextModel(for: voiceAction) && snapshot.textBackend != .basic {
                    phase = .processing
                    do {
                        let processed = try await process(text: cleaned, selection: inputTarget?.selection ?? "", action: voiceAction, settings: snapshot)
                        output = voiceAction == .dictate ? try TextProcessing.checkedDictationOutput(processed, source: cleaned) : processed
                        if voiceAction == .dictate, (snapshot.dictationLayout ?? .automatic) == .automatic, ParagraphLayout.needsLayout(output),
                           let laidOut = try? await complete(prompt: ParagraphLayout.prompt(output), settings: snapshot) {
                            output = ParagraphLayout.accept(laidOut, original: output)
                        }
                        aiFormatted = true
                    }
                    catch is CancellationError { throw CancellationError() }
                    catch {
                        result = cleaned
                        if voiceAction == .dictate { notice = "AI 整理未完成，已保留原始辨識文字。" }
                        else if voiceAction == .hyday { notice = "AI 整理未完成，已記成一般列點。" }
                        else { throw error }
                    }
                }
                try Task.checkCancellation(); guard sessionID == current else { return }
                output = TextProcessing.formatOutput(output, action: voiceAction, settings: snapshot)
                result = output
                var delivered = false
                if voiceAction == .hyday {
                    // Kept as the result first, so a failed write still leaves the text to copy.
                    let formatted = aiFormatted ? HydayEntryFormatting.entry(output, time: HydayEntryFormatting.time(spokeAt)) : ""
                    let entry = HydayEntryFormatting.stamped(formatted.isEmpty ? HydayVault.bullet(output) : formatted,
                                                             time: HydayEntryFormatting.time(spokeAt)); result = entry
                    guard let root = hydayRoot else { throw TalkError("找不到 Hyday 資料夾，請到 Hyday 頁重新設定。") }
                    try await Task.detached(priority: .userInitiated) {
                        try HydayVault(root: root).appendToJournal(entry)
                    }.value
                    notice = notice.isEmpty ? "已記到 Hyday 今天的日誌。" : notice + " 已記到 Hyday 今天的日誌。"
                } else if snapshot.autoInsert && voiceAction != .ask {
                    let message: String
                    do {
                        message = try await TextInsertion.insert(output, target: inputTarget)
                        if voiceAction == .dictate { watchCorrections(of: output, at: inputTarget, settings: snapshot) }
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation(); guard sessionID == current else { return }
                        TextInsertion.copy(output)
                        message = "文字已複製，可直接貼上。"
                    }
                    delivered = true
                    notice = notice.isEmpty ? message : notice + " " + message
                } else { notice = notice.isEmpty ? "文字已保留，可複製到需要的地方。" : notice }
                try Task.checkCancellation(); guard sessionID == current else { return }
                let place = voiceAction == .hyday ? "Hyday" : (inputTarget?.name ?? "結果區")
                usage.record(words: TextProcessing.wordCount(output), seconds: duration,
                             app: place, action: voiceAction); saveUsage()
                if snapshot.saveHistory {
                    history.insert(DictationRecord(rawText: raw, text: voiceAction == .hyday ? result : output, action: voiceAction, backend: snapshot.speechBackend,
                        duration: duration, destination: place), at: 0)
                    history = Array(history.prefix(200)); saveHistory()
                }
                // Insertion or clipboard fallback finishes before hiding; the result remains available.
                phase = delivered ? .idle : .done; onPanelChange?()
                if voiceAction == .hyday {
                    // Confirm briefly, then get out of the way.
                    try? await Task.sleep(for: .seconds(2))
                    if sessionID == current, phase == .done { phase = .idle; onPanelChange?() }
                }
            } catch is CancellationError { }
            catch { if sessionID == current { fail(error) } }
        }
    }

    func cancel() {
        sessionID = UUID(); operation?.cancel(); operation = nil
        recordingTimer?.invalidate(); recordingTimer = nil; audio.cancel()
        phase = .idle; level = 0; elapsed = 0; transcript = ""; onPanelChange?()
    }
    func dismissPanel() { if phase.busy { cancel() } else { phase = .idle; onPanelChange?() } }
    func copyResult() { guard !result.isEmpty else { return }; TextInsertion.copy(result); notice = "已複製文字。" }
    func removeRecord(_ id: UUID) { history.removeAll { $0.id == id }; saveHistory() }
    func clearHistory() { history = []; saveHistory() }
    func report(_ error: Error) { notice = error.localizedDescription }
    var todayRecords: [DictationRecord] { history.filter { Calendar.current.isDateInToday($0.date) } }

    private func fail(_ error: Error) {
        recordingTimer?.invalidate(); recordingTimer = nil; audio.cancel()
        notice = error.localizedDescription; phase = .failed; level = 0; onPanelChange?()
    }
    private func saveSettings() {
        do { try store.save(settings, to: "settings.json") } catch { notice = "設定未儲存。請確認磁碟空間與資料夾權限。" }
    }
    private func saveUsage() {
        do { try store.save(usage, to: "usage.json") } catch { notice += " 使用統計未儲存，請確認磁碟空間。" }
    }

    private func saveHistory() {
        do { try store.save(history, to: "history.json") } catch { notice += " 紀錄未儲存，請確認磁碟空間。" }
    }

    private func validate(_ settings: TalkSettings, action: VoiceAction) throws {
        switch settings.speechBackend {
        case .system: break
        case .whisper:
            guard localModels.engineReady else { throw TalkError("辨識引擎尚未就緒，請重新安裝 Hyday Talk。") }
            guard SpeechCLIConfiguration.isReadableModel(settings.whisperModel) else {
                throw TalkError("請在「語音辨識」下載並選擇本機模型。")
            }
        case .cli:
            try SpeechCLIConfiguration.validate(settings)
        case .api: try validateAPI(settings.speechAPI, account: "speech")
        }
        if action != .dictate && action != .hyday && settings.textBackend == .basic { throw TalkError("翻譯與提問需要文字 AI，請在「文字整理」選擇本機 AI 或 API Key。") }
        guard settings.requiresTextModel(for: action) else { return }
        if settings.textBackend == .local {
            guard !(settings.localTextModel ?? "").isEmpty else { throw TalkError("請在「文字整理」選擇本機文字模型。") }
        } else if settings.textBackend == .cli {
            guard FileManager.default.isExecutableFile(atPath: (settings.textCLIExecutable as NSString).expandingTildeInPath) else { throw TalkError("請先選擇文字 CLI 的可執行檔。") }
            _ = try CLIArguments.parse(settings.textCLIArguments)
        } else if settings.textBackend == .api { try validateAPI(settings.textAPI, account: "text") }
    }
    private func validateAPI(_ api: APISettings, account: String) throws {
        let endpoint = try APIClient.endpoint(base: api.baseURL, path: "")
        guard !api.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw TalkError("請先填入模型名稱。") }
        if !["localhost", "127.0.0.1", "::1", "[::1]"].contains(endpoint.host ?? ""), KeyStore.read(account).isEmpty {
            throw TalkError("請先儲存 API Key。本機服務可以不填 Key。")
        }
    }

    private func process(text: String, selection: String, action: VoiceAction, settings: TalkSettings) async throws -> String {
        var notes: [HydayNote]?
        if action == .ask, settings.asksHydayNotes, settings.textBackend != .basic, let root = hydayRoot {
            notes = await HydaySearchService.notes(root: root, query: String([text, selection].filter { !$0.isEmpty }.joined(separator: " ").prefix(200)))
            try Task.checkCancellation()
        }
        let prompt = try TextProcessing.prompt(action: action, transcript: text, selection: selection, settings: settings, notes: notes)
        return settings.textBackend == .basic ? text : try await complete(prompt: prompt, settings: settings)
    }

    // MARK: Learning from corrections

    private struct PendingCorrection {
        let element: AXUIElement
        let pid: pid_t
        let location: Int
        let inserted: String
        let expires: Date
        /// Set once the caret moves inside the field, so edits made by someone else are not learned.
        var userEdited = false
    }

    private func watchCorrections(of inserted: String, at target: InputTarget?, settings: TalkSettings) {
        stopWatchingCorrections()
        // Judging needs the text AI; without it nothing is learned.
        guard settings.learnsFromCorrections, settings.textBackend != .basic,
              let target, let element = target.element, let location = target.selectionRange?.location else { return }
        pendingCorrection = PendingCorrection(element: element, pid: target.pid, location: location, inserted: inserted,
                                              expires: Date().addingTimeInterval(120))
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkCorrectionsIfLeft() }
        }
        correctionTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func stopWatchingCorrections() {
        correctionTimer?.invalidate(); correctionTimer = nil; pendingCorrection = nil
    }

    private func checkCorrectionsIfLeft() {
        guard let pending = pendingCorrection else { stopWatchingCorrections(); return }
        if Date() > pending.expires { stopWatchingCorrections(); return }
        guard TextInsertion.isEditing(pending.element, pid: pending.pid) else { checkCorrections(); return }
        if let caret = TextInsertion.caretLocation(pending.element), caret != pending.location + pending.inserted.utf16.count {
            pendingCorrection?.userEdited = true
        }
    }

    /// Reads the field once, after the user left it or started the next dictation; unreadable fields are skipped silently.
    private func checkCorrections() {
        guard var pending = pendingCorrection else { return }
        stopWatchingCorrections()
        // The next fn press can arrive between samples; check the caret one last time.
        if TextInsertion.isEditing(pending.element, pid: pending.pid),
           let caret = TextInsertion.caretLocation(pending.element), caret != pending.location + pending.inserted.utf16.count {
            pending.userEdited = true
        }
        guard Date() <= pending.expires, pending.userEdited,
              let following = TextInsertion.readBack(pending.element, from: pending.location, length: pending.inserted.utf16.count + 200)
        else { return }
        let corrections = CorrectionFinder.find(inserted: pending.inserted, following: following)
        guard !corrections.isEmpty else { return }
        let snapshot = settings
        // Learning follows the order of the user's edits, not the order the AI answers in.
        let previous = correctionTask
        correctionTask = Task { [weak self] in
            await previous?.value
            for correction in corrections {
                guard let prompt = try? CorrectionJudge.prompt(for: correction),
                      let answer = try? await self?.complete(prompt: prompt, settings: snapshot),
                      CorrectionJudge.isTerm(answer) else { continue }
                guard !Task.isCancelled, let self, self.settings.learnsFromCorrections else { return }
                DictionaryLearning.learn(correction, into: &self.settings)
            }
        }
    }

    private func complete(prompt: String, settings: TalkSettings) async throws -> String {
        switch settings.textBackend {
        case .basic: throw TalkError("基礎整理沒有文字 AI。")
        case .local: return try await LocalTextClient.complete(prompt: prompt, model: settings.localTextModel ?? "")
        case .api: return try await APIClient.complete(prompt: prompt, settings: settings.textAPI, key: KeyStore.read("text"))
        case .cli:
            let arguments = CLIArguments.expand(try CLIArguments.parse(settings.textCLIArguments), values: ["{prompt}": prompt])
            let output = try await ProcessRunner.run(executable: settings.textCLIExecutable, arguments: arguments, input: prompt, timeout: 120)
            guard !output.isEmpty else { throw TalkError("文字 CLI 未回傳內容。請設定工具將結果寫入標準輸出。") }
            return output
        }
    }
}
