import AppKit
import IOKit.hidsystem
import TalkCore

@main
struct ShortcutProbe {
    @MainActor static func main() async {
        let fn: CGEventFlags = .maskSecondaryFn
        let left = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | UInt64(NX_DEVICELSHIFTKEYMASK))
        let right = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | UInt64(NX_DEVICERSHIFTKEYMASK))
        let both = left.union(right)
        var failures = 0
        var checks = 0
        func check(_ label: String, _ condition: Bool) {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "PASS" : "FAIL") \(label)")
        }
        func replay(_ label: String, expected: [ShortcutAction], busy: Bool = false,
                    events: [(CGEventType, UInt16, CGEventFlags)]) async {
            let shortcuts = GlobalShortcuts()
            var actions: [ShortcutAction] = []
            shortcuts.isBusy = { busy }
            shortcuts.onAction = { actions.append($0) }
            for (type, code, flags) in events { _ = shortcuts.replay(type: type, code: code, flags: flags) }
            try? await Task.sleep(nanoseconds: 10_000_000)
            check("\(label): \(actions)", actions == expected)
        }
        await replay("plain fn", expected: [.voice(.dictate)], events: [(.flagsChanged, 63, fn), (.flagsChanged, 63, [])])
        await replay("left Shift then fn", expected: [.voice(.translate)], events: [
            (.flagsChanged, 56, left), (.flagsChanged, 63, fn.union(left)),
            (.flagsChanged, 63, left), (.flagsChanged, 56, [])])
        await replay("fn then left Shift", expected: [.voice(.translate)], events: [
            (.flagsChanged, 63, fn), (.flagsChanged, 56, fn.union(left)),
            (.flagsChanged, 56, fn), (.flagsChanged, 63, [])])
        await replay("left Shift already held when tap starts", expected: [.voice(.translate)], events: [
            (.flagsChanged, 63, fn.union(left)), (.flagsChanged, 63, left)])
        await replay("repeat modifier events", expected: [.voice(.translate)], events: [
            (.flagsChanged, 63, fn), (.flagsChanged, 56, fn.union(left)),
            (.flagsChanged, 56, fn.union(left)), (.flagsChanged, 63, left), (.flagsChanged, 56, [])])
        await replay("both Shift keys, left released first", expected: [.voice(.translate)], events: [
            (.flagsChanged, 60, right), (.flagsChanged, 56, both), (.flagsChanged, 63, fn.union(both)),
            (.flagsChanged, 56, fn.union(right)), (.flagsChanged, 63, right), (.flagsChanged, 60, [])])
        await replay("right Shift does not start translation", expected: [], events: [
            (.flagsChanged, 60, right), (.flagsChanged, 63, fn.union(right)),
            (.flagsChanged, 63, right), (.flagsChanged, 60, [])])
        await replay("fn then right Shift does not fall back to dictation", expected: [], events: [
            (.flagsChanged, 63, fn), (.flagsChanged, 60, fn.union(right)),
            (.flagsChanged, 60, fn), (.flagsChanged, 63, [])])
        await replay("Command fn remains a system chord", expected: [], events: [
            (.flagsChanged, 55, .maskCommand), (.flagsChanged, 63, fn.union(.maskCommand)),
            (.flagsChanged, 63, .maskCommand), (.flagsChanged, 55, [])])
        await replay("fn then Command remains a system chord", expected: [], events: [
            (.flagsChanged, 63, fn), (.flagsChanged, 55, fn.union(.maskCommand)),
            (.flagsChanged, 55, fn), (.flagsChanged, 63, [])])
        await replay("Command left Shift fn does not translate", expected: [], events: [
            (.flagsChanged, 63, fn.union(left).union(.maskCommand)), (.flagsChanged, 63, left.union(.maskCommand))])
        await replay("fn Space", expected: [.voice(.ask)], events: [
            (.flagsChanged, 63, fn), (.keyDown, 49, fn), (.keyUp, 49, fn), (.flagsChanged, 63, [])])
        await replay("other fn chord", expected: [], events: [
            (.flagsChanged, 63, fn), (.keyDown, 123, fn), (.flagsChanged, 63, [])])
        await replay("Escape while recording", expected: [.cancel], busy: true, events: [(.keyDown, 53, []), (.keyUp, 53, [])])
        await replay("tap reset loses no old modifier state", expected: [.voice(.translate), .voice(.dictate)], events: [
            (.flagsChanged, 63, fn.union(left)), (.tapDisabledByTimeout, 0, []),
            (.flagsChanged, 63, fn), (.flagsChanged, 63, [])])
        let adapter = GlobalShortcuts()
        check("fn down consumed", adapter.replay(type: .flagsChanged, code: 63, flags: fn))
        check("fn Space down consumed", adapter.replay(type: .keyDown, code: 49, flags: fn))
        check("fn Space up consumed after fn release", {
            _ = adapter.replay(type: .flagsChanged, code: 63, flags: [])
            return adapter.replay(type: .keyUp, code: 49, flags: [])
        }())
        check("ordinary Space passed through", !adapter.replay(type: .keyDown, code: 49, flags: []))
        print("\(checks) checks; \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
