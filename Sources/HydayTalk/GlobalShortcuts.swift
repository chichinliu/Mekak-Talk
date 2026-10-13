import AppKit
import IOKit.hidsystem
import TalkCore

@MainActor
final class GlobalShortcuts {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var state = FnShortcutState()
    private var swallowedSpace = false
    private var swallowedEscape = false
    var isBusy: () -> Bool = { false }
    var onAction: ((ShortcutAction) -> Void)?
    var onAvailability: ((Bool) -> Void)?

    @discardableResult func start() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { onAvailability?(false); return false }
        let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: shortcutCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { onAvailability?(false); return false }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true); onAvailability?(true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; state.reset()
        swallowedSpace = false; swallowedEscape = false; onAvailability?(false)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            state.reset(); swallowedSpace = false; swallowedEscape = false
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        var action: ShortcutAction?
        var consume = false
        if type == .flagsChanged {
            // A session key-state query can lag inside a head-insert event tap.
            // Use this event's device flags to distinguish left and right Shift,
            // including when both keys are down or Shift predates tap startup.
            let leftShift = event.flags.rawValue & UInt64(NX_DEVICELSHIFTKEYMASK) != 0
            let rightShift = event.flags.rawValue & UInt64(NX_DEVICERSHIFTKEYMASK) != 0
            let otherModifier = (rightShift && !leftShift) || !event.flags.intersection([.maskCommand, .maskAlternate]).isEmpty
            let control = event.flags.contains(.maskControl)
            if code == 63 {
                action = state.fnChanged(down: event.flags.contains(.maskSecondaryFn),
                                         leftShift: leftShift, otherModifier: otherModifier, control: control)
                consume = true
            } else if code == 59 || code == 62 {
                // fn + Control starts a text question.
                action = otherModifier ? nil : state.controlChanged(down: control)
                if otherModifier { state.otherModifierChanged() }
                consume = action != nil
            } else if code == 56, !otherModifier {
                action = state.shiftChanged(down: leftShift)
                consume = action != nil
            } else if otherModifier {
                state.otherModifierChanged()
            }
        } else if type == .keyDown {
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            action = state.keyDown(code: code, repeated: repeated, recording: isBusy())
            if code == 49, state.fnDown { swallowedSpace = true; consume = true }
            if code == 53, isBusy() { swallowedEscape = true; consume = true }
        } else if type == .keyUp {
            if code == 49, swallowedSpace { swallowedSpace = false; consume = true }
            if code == 53, swallowedEscape { swallowedEscape = false; consume = true }
        }
        // Never perform permission requests or audio work inside the event-tap callback.
        if let action { DispatchQueue.main.async { [weak self] in self?.onAction?(action) } }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}

private func shortcutCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let context else { return Unmanaged.passUnretained(event) }
    return MainActor.assumeIsolated {
        Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
    }
}
