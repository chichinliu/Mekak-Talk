import Foundation

public enum ShortcutAction: Equatable { case voice(VoiceAction), cancel }

/// Fn is a modifier, so Carbon's normal hotkey registration cannot represent it.
/// A tap is committed on release; chords never also trigger the plain Fn action.
public struct FnShortcutState {
    public private(set) var fnDown = false
    private var usedInChord = false
    private var leftShiftDown = false
    public init() {}

    public mutating func fnChanged(down: Bool, leftShift: Bool, otherModifier: Bool = false) -> ShortcutAction? {
        guard down != fnDown else { return nil }
        fnDown = down
        leftShiftDown = leftShift
        if down {
            usedInChord = leftShift || otherModifier
            return leftShift && !otherModifier ? .voice(.translate) : nil
        }
        return usedInChord ? nil : .voice(.dictate)
    }

    public mutating func shiftChanged(down: Bool) -> ShortcutAction? {
        let newlyDown = down && !leftShiftDown
        leftShiftDown = down
        guard fnDown, newlyDown, !usedInChord else { return nil }
        usedInChord = true
        return .voice(.translate)
    }

    public mutating func otherModifierChanged() {
        if fnDown { usedInChord = true }
    }

    public mutating func keyDown(code: UInt16, repeated: Bool, recording: Bool) -> ShortcutAction? {
        if code == 53, recording, !repeated { return .cancel }
        guard fnDown, !repeated else { return nil }
        let canAsk = !usedInChord
        usedInChord = true
        return code == 49 && canAsk ? .voice(.ask) : nil
    }
    public mutating func reset() { self = FnShortcutState() }
}
