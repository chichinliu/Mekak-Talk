import SwiftUI
import AppKit
import TalkCore

private final class NonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class VoicePanelPresentation: ObservableObject {
    @Published var expanded = false
}

@MainActor
final class VoicePanel {
    private let panel: NonactivatingPanel
    private let model: AppModel
    private let presentation = VoicePanelPresentation()
    private var lastPhase: CapturePhase = .idle
    init(model: AppModel) {
        self.model = model
        panel = NonactivatingPanel(contentRect: NSRect(x: 0, y: 0, width: LayoutToken.voicePanelWidth, height: LayoutToken.voicePanelHeight),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: VoicePanelContent(model: model, presentation: presentation,
            onSizeChange: { [weak self] in self?.refresh() }))
        panel.isReleasedWhenClosed = false
    }
    func refresh() {
        if lastPhase != model.phase {
            lastPhase = model.phase
            presentation.expanded = model.phase == .failed || (model.phase == .done && model.action == .ask)
        }
        guard model.phase != .idle else { panel.orderOut(nil); return }
        let height = presentation.expanded ? LayoutToken.voiceDetailHeight : LayoutToken.voicePanelHeight
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrame(NSRect(x: frame.midX - LayoutToken.voicePanelWidth / 2, y: frame.minY + LayoutToken.voicePanelBottomInset,
            width: LayoutToken.voicePanelWidth, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

private struct VoicePanelContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: VoicePanelPresentation
    let onSizeChange: () -> Void
    var body: some View {
        VoiceBarView(state: VoiceBarState(model: model), expanded: $presentation.expanded,
            actions: VoiceBarActions(finish: model.finish, dismiss: model.dismissPanel, copy: model.copyResult,
                openMain: { model.dismissPanel(); model.showWindow?() }, resize: onSizeChange))
            .onChange(of: model.phase) { _, _ in onSizeChange() }
    }
}

struct VoiceBarState {
    let phase: CapturePhase
    var elapsed: TimeInterval = 0
    var level: Double = 0
    var transcript = ""
    var result = ""
    var notice = ""
    var action: VoiceAction = .dictate
    var destination = "結果區"
    var actionTitle: String { action.title }
}

extension VoiceBarState {
    @MainActor init(model: AppModel) {
        self.init(phase: model.phase, elapsed: model.elapsed, level: model.level, transcript: model.transcript,
            result: model.result, notice: model.notice, action: model.action, destination: model.destination)
    }
}

struct VoiceBarActions {
    var finish: () -> Void = {}
    var dismiss: () -> Void = {}
    var copy: () -> Void = {}
    var openMain: () -> Void = {}
    var resize: () -> Void = {}
}

struct VoiceBarView: View {
    let state: VoiceBarState
    @Binding var expanded: Bool
    var actions = VoiceBarActions()
    private var terminal: Bool { state.phase == .done || state.phase == .failed }
    private var radius: CGFloat { expanded ? 16 : 26 }
    private var elapsedText: String { String(format: "%02d:%02d", Int(state.elapsed) / 60, Int(state.elapsed) % 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls.frame(height: 32)
            if expanded { details }
        }.padding(LayoutToken.voicePanelPadding).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.border, lineWidth: 1))
            .padding(2).font(Typography.font(.caption)).lineSpacing(Typography.paragraphSpacing)
            .foregroundStyle(Palette.ink).tint(Palette.action).preferredColorScheme(.light).focusEffectDisabled()
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if state.phase.busy && state.phase != .recording {
                ProgressView().controlSize(.regular).scaleEffect(0.5).frame(width: 16, height: 16)
            } else {
                Image(systemName: state.phase == .recording ? "waveform" : (state.phase == .failed ? "exclamationmark.circle.fill" : "checkmark.circle.fill"))
                    .font(IconToken.font(.badge, weight: .semibold))
                    .foregroundStyle(state.phase == .recording ? Palette.accent : Palette.action)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(compactTitle).font(Typography.font(.caption, weight: .semibold)).lineLimit(1)
                    .help(state.notice.isEmpty ? compactTitle : state.notice)
                if state.phase == .recording {
                    Text(elapsedText).font(Typography.font(.caption)).monospacedDigit().foregroundStyle(Palette.muted)
                        .fixedSize().accessibilityLabel("錄音時間").accessibilityValue(elapsedText)
                }
            }.fixedSize(horizontal: true, vertical: false)
            if state.phase == .recording { levelMeter }
            Spacer(minLength: 0)
            if state.phase == .recording {
                control("stop.fill", label: "完成錄音 · fn", emphasized: true, action: actions.finish)
            } else if terminal && !state.result.isEmpty {
                control("doc.on.doc", label: "複製文字", emphasized: true, action: actions.copy)
            }
            if state.phase != .recording {
                control(expanded ? "chevron.up" : "chevron.down", label: expanded ? "收合詳情" : "展開詳情") {
                    expanded.toggle(); actions.resize()
                }
            }
            control("xmark", label: state.phase.busy ? "取消 · esc" : "關閉", action: actions.dismiss)
        }
    }

    private var compactTitle: String {
        switch state.phase {
        case .idle: return "待機"
        case .preparing: return "準備中"
        case .recording:
            switch state.action {
            case .dictate: return "錄音中"
            case .translate: return "翻譯錄音"
            case .ask: return "提問錄音"
            }
        case .transcribing: return "辨識中"
        case .processing:
            switch state.action {
            case .dictate: return "整理中"
            case .translate: return "翻譯中"
            case .ask: return "回應中"
            }
        case .done: return "已完成"
        case .failed: return "處理失敗"
        }
    }

    private var levelMeter: some View {
        let level = min(1, max(0, state.level))
        return HStack(spacing: 2) {
            ForEach(0..<19, id: \.self) { index in
                let envelope = max(0.2, 1 - abs(Double(index) - 9) / 9)
                Capsule().fill(Palette.accent)
                    .frame(width: 2, height: 3 + CGFloat(level * envelope) * CGFloat([12, 20, 15, 25, 18][index % 5]))
            }
        }.frame(width: LayoutToken.voiceLevelWidth, height: 20)
            .accessibilityElement(children: .ignore).accessibilityLabel("麥克風音量")
            .accessibilityValue("\(Int(level * 100)) 百分比")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if state.phase == .recording {
                        Text(state.transcript.isEmpty ? "請開始說話" : state.transcript).font(Typography.font(.body)).textSelection(.enabled)
                    } else if terminal {
                        if !state.result.isEmpty { Text(state.result).font(Typography.font(.body)).textSelection(.enabled) }
                        if !state.notice.isEmpty { Text(state.notice).foregroundStyle(Palette.muted).textSelection(.enabled) }
                    } else {
                        Text(state.phase == .preparing ? "請允許麥克風與必要的辨識權限。" : "聽寫或翻譯送出文字後會關閉面板，其他結果保留供複製。")
                            .foregroundStyle(Palette.muted)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: .infinity)
            if terminal {
                Button("開啟主視窗", action: actions.openMain).buttonStyle(AlignButtonStyle()).controlSize(.regular)
            } else {
                Text("\(state.actionTitle) · \(state.destination)").foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle).help("\(state.actionTitle) · \(state.destination)")
            }
        }
    }

    private func control(_ symbol: String, label: String, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(IconToken.font(.small, weight: .semibold))
                .frame(width: LayoutToken.voiceControlSize, height: LayoutToken.voiceControlSize)
                .foregroundStyle(emphasized ? (state.phase == .recording ? Palette.danger : Palette.action) : Palette.muted)
                .background(emphasized ? (state.phase == .recording ? Palette.dangerSurface : Palette.actionSurface) : Color.clear, in: Circle())
                .contentShape(Rectangle())
        }.buttonStyle(.plain).pointingCursor().help(label).accessibilityLabel(label)
    }
}
