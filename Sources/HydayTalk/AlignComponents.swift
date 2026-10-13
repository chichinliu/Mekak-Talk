import SwiftUI
import AppKit

// Shared buttons, segmented control, inputs and status badge.
enum AlignButtonKind { case primary, accent, secondary, ghost, destructive }

struct AlignButtonStyle: ButtonStyle {
    var kind: AlignButtonKind = .secondary
    var prominent = false
    var pressFeedback = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    private var foreground: Color {
        if !enabled { return Palette.muted }
        switch kind {
        case .primary, .accent: return .white
        case .destructive: return Palette.danger
        case .secondary, .ghost: return Palette.ink
        }
    }
    private var background: Color {
        if !enabled { return Palette.subtleSurface }
        switch kind {
        case .primary: return hovered ? Palette.actionInk : Palette.action
        case .accent: return hovered ? Palette.accentInk : Palette.accent
        case .secondary: return hovered ? Palette.border : Palette.subtleSurface
        case .ghost: return hovered ? Palette.selectedSurface : .clear
        case .destructive: return hovered ? Palette.dangerSurface : Palette.surface
        }
    }
    private var filled: Bool { enabled && (kind == .primary || kind == .accent) }
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Typography.font(.body, weight: .medium))
            .padding(.horizontal, prominent ? 16 : 12).padding(.vertical, 8).frame(minHeight: prominent ? 44 : 36)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.controlRadius))
            .overlay(filled ? RoundedRectangle(cornerRadius: DesignTokens.Surfaces.controlRadius)
                .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)) : nil)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.controlRadius)
                .stroke(filled ? Color.black.opacity(0.12) : (kind == .destructive ? Palette.border : .clear), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.controlRadius))
            .scaleEffect(configuration.isPressed && enabled && pressFeedback && !reduceMotion ? 0.96 : 1)
            .onHover { hovered = $0 }.pointingCursor()
    }
}

struct AlignNavigationStyle: ButtonStyle {
    var selected = false
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 10
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .background(selected ? Palette.surface : (hovered ? Color.black.opacity(0.04) : .clear),
                        in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: selected ? Color.black.opacity(0.06) : .clear, radius: 1, y: 1)
            .shadow(color: selected ? Color.black.opacity(0.06) : .clear, radius: 6, y: 3)
            .contentShape(RoundedRectangle(cornerRadius: 8)).onHover { hovered = $0 }.pointingCursor()
    }
}

struct AlignTextFieldStyle: TextFieldStyle {
    var monospaced = false
    @FocusState private var focused: Bool
    func _body(configuration: TextField<_Label>) -> some View {
        configuration.textFieldStyle(.plain).focused($focused)
            .font(Typography.font(.body, design: monospaced ? .monospaced : .default))
            .padding(.horizontal, 11).padding(.vertical, 9).frame(minHeight: 36)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
    }
}

struct AlignMenuPicker<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var showsTitle = true
    @Environment(\.isEnabled) private var enabled
    @State private var focused = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsTitle { Text(title).font(Typography.font(.caption, weight: .medium)) }
            NativeAlignPopUp(title: title, values: values, selection: $selection, label: label, enabled: enabled,
                             onFocus: { focused = $0 })
                .frame(height: 36)
                .background(enabled ? Palette.surface : Palette.subtleSurface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)).pointingCursor()
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.down").font(IconToken.font(.small, weight: .medium))
                        .foregroundStyle(Palette.muted).padding(.trailing, 11).allowsHitTesting(false).accessibilityHidden(true)
                }.help(label(selection))
        }
    }
}

private final class AlignPopUpCell: NSPopUpButtonCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var title = super.titleRect(forBounds: rect)
        title.origin.x = max(title.minX, rect.minX + 11)
        title.size.width = max(0, rect.maxX - 34 - title.minX)
        return title
    }
}

private final class AlignPopUpButton: NSPopUpButton {
    var onFocus: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus?(false) }
        return accepted
    }
}

private struct NativeAlignPopUp<Value: Hashable>: NSViewRepresentable {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    let enabled: Bool
    let onFocus: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> AlignPopUpButton {
        let button = AlignPopUpButton(frame: .zero, pullsDown: false)
        button.cell = AlignPopUpCell(textCell: "", pullsDown: false)
        button.isBordered = false; button.focusRingType = .none
        button.font = .systemFont(ofSize: Typography.pointSize(.body))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        button.cell?.usesSingleLineMode = true; button.cell?.lineBreakMode = .byTruncatingMiddle
        button.target = context.coordinator; button.action = #selector(Coordinator.select(_:))
        return button
    }
    func updateNSView(_ button: AlignPopUpButton, context: Context) {
        context.coordinator.parent = self
        let titles = values.map(label)
        if button.itemTitles != titles { button.removeAllItems(); button.addItems(withTitles: titles) }
        if let index = values.firstIndex(of: selection), button.indexOfSelectedItem != index { button.selectItem(at: index) }
        button.isEnabled = enabled
        button.setAccessibilityLabel(title)
        button.toolTip = label(selection)
        button.onFocus = { value in DispatchQueue.main.async { onFocus(value) } }
    }
    final class Coordinator: NSObject {
        var parent: NativeAlignPopUp
        init(_ parent: NativeAlignPopUp) { self.parent = parent }
        @objc func select(_ button: NSPopUpButton) {
            let index = button.indexOfSelectedItem
            guard parent.values.indices.contains(index) else { return }
            parent.selection = parent.values[index]
        }
    }
}

struct AlignChoiceStyle: ButtonStyle {
    let selected: Bool
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected || hovered ? Palette.surface : Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Palette.action : DesignTokens.Surfaces.border, lineWidth: selected ? 1.5 : 1))
            .background(RoundedRectangle(cornerRadius: 19).fill(selected ? Palette.actionBorder.opacity(0.7) : .clear).padding(-3))
            .shadow(color: selected ? Palette.action.opacity(0.18) : DesignTokens.Surfaces.contactShadow, radius: selected ? 6 : 1, y: selected ? 4 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16)).onHover { hovered = $0 }.pointingCursor()
    }
}

struct AlignSegmentedPicker<Value: Hashable>: View {
    let title: String
    let values: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Environment(\.isEnabled) private var enabled
    @FocusState private var focused: Value?
    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button { selection = value; focused = value } label: {
                    Text(label(value)).font(Typography.font(.body, weight: .medium))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 28)
                }.buttonStyle(AlignSegmentStyle(selected: selection == value))
                    .focusable().focusEffectDisabled()
                    .focused($focused, equals: value)
                    .accessibilityAddTraits(selection == value ? [.isSelected] : [])
            }
        }.padding(3).background(Palette.subtleSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.04), lineWidth: 1))
            .accessibilityElement(children: .contain).accessibilityLabel(title)
            .onKeyPress(.leftArrow) { step(-1) }
            .onKeyPress(.rightArrow) { step(1) }
    }
    private func step(_ offset: Int) -> KeyPress.Result {
        guard enabled, let index = values.firstIndex(of: focused ?? selection) else { return .ignored }
        let next = min(values.count - 1, max(0, index + offset))
        selection = values[next]; focused = values[next]
        return .handled
    }
}

private struct AlignSegmentStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(enabled && selected ? Palette.ink : Palette.muted)
            .background(selected ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.black.opacity(0.06) : .clear, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 6)).pointingCursor()
    }
}

struct AlignStatusBadge: View {
    let title: String
    var ready = false
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(ready ? Palette.success : Palette.warning).frame(width: 7, height: 7)
                .background(Circle().fill(ready ? Palette.successSurface : Palette.warningSurface).padding(-3))
                .accessibilityHidden(true)
            Text(title)
        }
            .font(Typography.font(.caption, weight: .semibold))
            .foregroundStyle(ready ? Palette.successInk : Palette.warningInk)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Palette.surface, in: Capsule())
            .overlay(Capsule().stroke(ready ? Palette.successBorder : Palette.warningBorder, lineWidth: 1))
    }
}

struct WaveformView: View {
    var level: Double
    var count = 25
    var color: Color = Palette.accent
    var active = true
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                let center = Double(count - 1) / 2
                let envelope = max(0.15, 1 - abs(Double(index) - center) / max(1, center))
                let texture = [0.6, 0.9, 0.5, 0.75, 1.0][index % 5]
                Capsule().fill(color.opacity(active ? 1 : 0.65))
                    .frame(width: 3, height: 3 + (active ? min(1, max(0, level)) : 0.75) * envelope * texture * 36)
            }
        }.frame(height: 40).accessibilityHidden(true)
    }
}

struct ExamplePair: View {
    let input: String
    let output: String
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            example("說話內容", text: input, emphasized: false)
            example("整理結果", text: output, emphasized: true)
        }
    }
    private func example(_ title: String, text: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            Text(text).font(Typography.font(.body, weight: emphasized ? .medium : .regular))
                .lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(emphasized ? 12 : 0)
                .background(emphasized ? Palette.subtleSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PointingCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    @State private var pushed = false
    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering && enabled && !pushed { NSCursor.pointingHand.push(); pushed = true }
            else if !hovering && pushed { NSCursor.pop(); pushed = false }
        }
        .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
    }
}

extension View {
    func pointingCursor() -> some View { modifier(PointingCursor()) }
}
