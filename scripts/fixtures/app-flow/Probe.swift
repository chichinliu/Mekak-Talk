import AppKit
import TalkCore

@main struct AppFlowProbe {
    @MainActor static func main() async {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }
        func waitForTask(_ model: AppModel, starting: Bool = false) async {
            for _ in 0..<1000 {
                if starting ? model.phase == .recording || !model.phase.busy : !model.phase.busy { return }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        let element = AXUIElementCreateApplication(0)
        let editable = InputTarget(name: "測試編輯器", selection: "", element: element, editable: true, secure: false)
        let noFieldCases: [(String, InputTarget?)] = [
            ("no destination app", nil),
            ("no focused element", InputTarget(name: "測試 App", selection: "", element: nil, editable: true, secure: false)),
            ("non-editable focus", InputTarget(name: "測試 App", selection: "", element: element, editable: false, secure: false)),
        ]
        for (name, target) in noFieldCases {
            TextInsertion.reset(); TextInsertion.capturedTarget = target
            let model = AppModel(); model.configureForFlow()
            model.begin()
            await waitForTask(model, starting: true)
            check(model.phase == .recording, "\(name): recording starts without a failed panel")
            model.finish(); await waitForTask(model)
            check(!model.result.isEmpty && TextInsertion.copied == [model.result] && TextInsertion.inserted.isEmpty,
                  "\(name): final formatted result is copied exactly once")
            check(model.phase == .idle && model.notice.contains("已複製"),
                  "\(name): copying completes without a persistent failure panel")
            check(model.history.count == 1 && model.history.first?.text == model.result,
                  "\(name): copied output remains in history")
        }
        for action in [VoiceAction.dictate, .translate] {
            TextInsertion.reset(); TextInsertion.capturedTarget = editable
            let model = AppModel(); model.primeForFlow(action: action)
            model.finish(); await waitForTask(model)
            check(model.phase == .idle && TextInsertion.inserted == [model.result] && TextInsertion.copied.isEmpty,
                  "\(action.rawValue): valid input still inserts and dismisses")
            check(model.history.count == 1, "\(action.rawValue): insertion retains history")
            TextInsertion.reset()
            let noTarget = AppModel(); noTarget.primeForFlow(action: action)
            noTarget.finish(); await waitForTask(noTarget)
            check(noTarget.phase == .idle && !noTarget.result.isEmpty && TextInsertion.copied == [noTarget.result],
                  "\(action.rawValue): no input uses automatic clipboard fallback")
        }
        TextInsertion.reset(); TextInsertion.capturedTarget = editable; TextInsertion.mode = .failure
        let changed = AppModel(); changed.primeForFlow()
        changed.finish(); await waitForTask(changed)
        check(changed.phase == .idle && TextInsertion.copied == [changed.result] && changed.notice.contains("已複製"),
              "changed input position copies instead of showing an error")
        TextInsertion.reset()
        let manual = AppModel(); manual.primeForFlow(autoInsert: false)
        manual.finish(); await waitForTask(manual)
        check(manual.phase == .done && !manual.result.isEmpty && TextInsertion.copied.isEmpty && TextInsertion.inserted.isEmpty,
              "explicit manual-result mode is preserved")
        TextInsertion.reset()
        let question = AppModel(); question.primeForFlow(action: .ask)
        question.finish(); await waitForTask(question)
        check(question.phase == .done && !question.result.isEmpty && TextInsertion.copied.isEmpty && TextInsertion.inserted.isEmpty,
              "questions remain available without automatic insertion or copying")
        TextInsertion.reset()
        TextInsertion.capturedTarget = InputTarget(name: "密碼欄位", selection: "", element: element, editable: true, secure: true)
        let secure = AppModel(); secure.configureForFlow(); secure.begin()
        await waitForTask(secure, starting: true)
        check(secure.phase == .failed && secure.notice.contains("密碼") && TextInsertion.copied.isEmpty,
              "existing secure-field guard is preserved")
        TextInsertion.reset(); AudioCapture.text = ""
        let empty = AppModel(); empty.primeForFlow()
        empty.finish(); await waitForTask(empty)
        check(empty.phase == .failed && empty.result.isEmpty && TextInsertion.copied.isEmpty && empty.history.isEmpty,
              "empty recognition still reports its actual error without copying")
        TextInsertion.reset(); TextInsertion.capturedTarget = editable; TextInsertion.mode = .hold
        let cancelled = AppModel(); cancelled.primeForFlow(); cancelled.finish()
        for _ in 0..<1000 {
            if TextInsertion.continuation != nil { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        check(cancelled.phase == .transcribing && TextInsertion.continuation != nil,
              "panel waits for insertion to finish")
        cancelled.cancel()
        TextInsertion.continuation?.resume(); TextInsertion.continuation = nil
        await waitForTask(cancelled)
        try? await Task.sleep(nanoseconds: 10_000_000)
        check(cancelled.phase == .idle && TextInsertion.copied.isEmpty && cancelled.history.isEmpty,
              "cancelled operation cannot copy or save a completed result")
        TextInsertion.reset(); TextInsertion.capturedTarget = editable; TextInsertion.mode = .hold
        let newer = AppModel(); newer.primeForFlow(); newer.finish()
        for _ in 0..<1000 {
            if TextInsertion.continuation != nil { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        newer.primeForFlow()
        TextInsertion.continuation?.resume(); TextInsertion.continuation = nil
        try? await Task.sleep(nanoseconds: 10_000_000)
        check(newer.phase == .recording && TextInsertion.copied.isEmpty && newer.history.isEmpty,
              "stale completion cannot hide or copy over the next recording")
        newer.cancel()
        for cancel in [true, false] {
            TextInsertion.reset(); TextInsertion.capturedTarget = editable; TextInsertion.mode = .holdFailure
            let abandoned = AppModel(); abandoned.primeForFlow(); abandoned.finish()
            for _ in 0..<1000 {
                if TextInsertion.continuation != nil { break }
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            if cancel { abandoned.cancel() } else { abandoned.primeForFlow() }
            TextInsertion.continuation?.resume(); TextInsertion.continuation = nil
            try? await Task.sleep(nanoseconds: 10_000_000)
            check(abandoned.phase == (cancel ? .idle : .recording) && TextInsertion.copied.isEmpty && abandoned.history.isEmpty,
                  "\(cancel ? "cancelled" : "stale") failed insertion cannot trigger clipboard fallback")
            abandoned.cancel()
        }
        print("Checks: \(checks), failures: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }
}
