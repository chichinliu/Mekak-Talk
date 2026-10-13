import AppKit
import AVFoundation
import Speech
import SwiftUI

enum PermissionKind: String, Identifiable {
    case microphone, speech, accessibility
    var id: String { rawValue }
    var title: String {
        switch self {
        case .microphone: return "麥克風"
        case .speech: return "語音辨識"
        case .accessibility: return "輔助使用"
        }
    }
    var symbol: String {
        switch self {
        case .microphone: return "mic"
        case .speech: return "waveform"
        case .accessibility: return "keyboard"
        }
    }
    var purpose: String {
        switch self {
        case .microphone: return "允許 Hyday Talk 透過麥克風錄製語音。"
        case .speech: return "允許 macOS 將語音辨識為文字，僅系統辨識需要此權限。"
        case .accessibility: return "允許在其他 App 使用 fn 快捷鍵，並將文字輸入目前的文字框。"
        }
    }
    var privacyPane: String {
        switch self {
        case .microphone: return "Microphone"
        case .speech: return "SpeechRecognition"
        case .accessibility: return "Accessibility"
        }
    }
    var supportURL: URL {
        switch self {
        case .microphone: return URL(string: "https://support.apple.com/guide/mac-help/control-access-to-the-microphone-on-mac-mchla1b1e1fe/mac")!
        case .speech: return URL(string: "https://support.apple.com/guide/mac-help/control-access-to-speech-recognition-on-mac-mchl48fbbd25/mac")!
        case .accessibility: return URL(string: "https://support.apple.com/guide/mac-help/allow-accessibility-apps-to-access-your-mac-mh43185/mac")!
        }
    }
}

enum PermissionAuthorization {
    case notDetermined, denied, restricted, granted
    var title: String {
        switch self {
        case .notDetermined: return "尚未設定"
        case .denied: return "尚未授權"
        case .restricted: return "受系統限制"
        case .granted: return "已開啟"
        }
    }
}

struct PermissionGuideView: View {
    @ObservedObject var model: AppModel
    let initialStep: PermissionKind?
    @State private var selected: PermissionKind = .microphone
    @State private var showTroubleshooting = false
    private var steps: [PermissionKind] { model.requiredPermissions }
    private var status: PermissionAuthorization { model.authorization(for: selected) }
    private var granted: Bool { model.permissionAllowed(selected) }
    private var index: Int { steps.firstIndex(of: selected) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                HydayLogo(size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("權限設定")
                        .font(Typography.font(.title, weight: .medium)).singleLineHeading()
                    Text("請完成 \(steps.count) 項權限設定，返回 App 後會自動更新狀態。")
                        .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Text("\(model.completedPermissionCount) / \(steps.count)")
                    .font(Typography.font(.caption, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Palette.ink).padding(.horizontal, 11).padding(.vertical, 5)
                    .background(Palette.surface, in: Capsule()).shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)
                    .accessibilityLabel("已完成 \(model.completedPermissionCount) 項，共 \(steps.count) 項權限")
            }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 18)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.element) { position, permission in
                        Button {
                            selected = permission; showTroubleshooting = false
                        } label: {
                            HStack(spacing: 10) {
                                if model.permissionAllowed(permission) {
                                    Image(systemName: "checkmark.circle.fill").font(IconToken.font(.badge)).foregroundStyle(Palette.success)
                                } else {
                                    Text("\(position + 1)").font(Typography.font(.caption, weight: .medium))
                                        .frame(width: 21, height: 21)
                                        .background(selected == permission ? Palette.accent : Palette.subtleSurface, in: Circle())
                                        .foregroundStyle(selected == permission ? Palette.onAccent : Palette.muted)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(permission.title).font(Typography.font(.caption, weight: .medium))
                                    Text(model.authorization(for: permission).title).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selected == permission ? Palette.surface : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                .shadow(color: selected == permission ? Color.black.opacity(0.08) : .clear, radius: 1.5, y: 1)
                        }.buttonStyle(.plain).pointingCursor().accessibilityAddTraits(selected == permission ? [.isSelected] : [])
                    }
                    Spacer()
                    if model.settings.speechBackend != .system {
                        Text("目前的辨識來源不需要 Apple 語音辨識權限。")
                            .font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing).padding(.horizontal, 8)
                    }
                    Label("由你在 macOS 確認授權", systemImage: "lock")
                        .font(Typography.font(.caption)).foregroundStyle(Palette.muted).padding(.horizontal, 8)
                }.frame(width: 180)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: selected.symbol).font(IconToken.font(.regular)).foregroundStyle(Palette.muted)
                                .frame(width: 34, height: 34).background(Palette.subtleSurface, in: Circle())
                            Text("開啟\(selected.title)").font(Typography.font(.cardTitle, weight: .medium)).singleLineHeading()
                            Spacer()
                            AlignStatusBadge(title: status.title, ready: granted)
                        }
                        Text(selected.purpose).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
                        if status == .restricted {
                            Label("這台 Mac 受系統限制，請檢查「螢幕使用時間」限制或洽詢管理者。", systemImage: "exclamationmark.circle")
                                .font(Typography.font(.caption)).foregroundStyle(Palette.ink).lineSpacing(Typography.paragraphSpacing)
                        } else if granted {
                            Label("這一步已完成，可以繼續下一步。", systemImage: "checkmark.circle.fill")
                                .font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.successInk)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Palette.successSurface, in: RoundedRectangle(cornerRadius: 10))
                        }
                        instructions
                        HStack(spacing: 10) {
                            if !granted && status != .restricted {
                                Button(primaryButtonTitle) { requestSelectedPermission() }
                                    .buttonStyle(AlignButtonStyle(kind: .primary)).controlSize(.large)
                                    .disabled(model.requestingPermission != nil)
                            }
                            Button("開啟\(selected.title)設定") { model.openPrivacy(selected.privacyPane) }
                                .buttonStyle(AlignButtonStyle()).controlSize(.large)
                        }
                        Text("返回 Hyday Talk 後會自動檢查；也可以按「重新檢查」。")
                            .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                        Divider()
                        DisclosureGroup(isExpanded: $showTroubleshooting) {
                            troubleshooting.padding(.top, 12)
                        } label: {
                            Text(selected == .accessibility ? "輔助使用設定疑難排解" : "權限授權疑難排解")
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        }.font(Typography.font(.caption, weight: .medium))
                        Link("查看 Apple 的\(selected.title)權限說明", destination: selected.supportURL).pointingCursor()
                            .font(Typography.font(.caption))
                        if model.completedPermissionCount == steps.count {
                            if model.shortcutReady {
                                VStack(alignment: .leading, spacing: 9) {
                                    Label("權限已就緒", systemImage: "checkmark.circle.fill").font(Typography.font(.body, weight: .semibold)).singleLineHeading()
                                    Text("打開備忘錄或其他 App，點一下文字框，按 fn 開始說話，再按 fn 完成。")
                                        .font(Typography.font(.caption)).lineSpacing(Typography.paragraphSpacing)
                                }.foregroundStyle(Palette.action).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.actionSurface, in: RoundedRectangle(cornerRadius: 12))
                            } else {
                                Label("權限已開啟，但 fn 尚未就緒。請完全結束 Hyday Talk，再重新開啟。", systemImage: "exclamationmark.circle")
                                    .font(Typography.font(.caption)).foregroundStyle(Palette.ink).lineSpacing(Typography.paragraphSpacing)
                            }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius))
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
                        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
                        .padding(4)
                }
            }.padding(.horizontal, 24).frame(maxHeight: .infinity, alignment: .top)
            Rectangle().fill(Palette.border).frame(height: 1).padding(.top, 16)
            HStack(spacing: 12) {
                Button("稍後設定") { model.showPermissionGuide = false }.buttonStyle(AlignButtonStyle(kind: .ghost)).foregroundStyle(Palette.muted)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("重新檢查") { model.refreshPermissions() }.buttonStyle(AlignButtonStyle())
                if model.permissionsReady {
                    Button("完成設定") { model.showPermissionGuide = false }.buttonStyle(AlignButtonStyle(kind: .primary)).keyboardShortcut(.defaultAction)
                } else if index < steps.count - 1 {
                    Button("下一步") { selected = steps[index + 1]; showTroubleshooting = false }
                        .buttonStyle(AlignButtonStyle(kind: .primary)).disabled(!granted).keyboardShortcut(.defaultAction)
                } else {
                    Button("完成設定") { model.showPermissionGuide = false }.buttonStyle(AlignButtonStyle(kind: .primary)).disabled(true)
                }
            }.controlSize(.large).padding(.horizontal, 24).padding(.vertical, 16)
        }.frame(width: LayoutToken.guideWidth, height: LayoutToken.guideHeight).background(Palette.workspace).foregroundStyle(Palette.ink)
            .font(Typography.font(.body)).lineSpacing(Typography.paragraphSpacing)
            .tint(Palette.action).preferredColorScheme(.light)
            .onAppear {
                model.refreshPermissions()
                selected = initialStep.flatMap { steps.contains($0) ? $0 : nil }
                    ?? steps.first(where: { !model.permissionAllowed($0) }) ?? .microphone
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshPermissions() }
            .onChange(of: model.settings.speechBackend) { _, _ in
                if !steps.contains(selected) { selected = .microphone }
            }
    }

    private var primaryButtonTitle: String {
        if model.requestingPermission == selected { return "請在 macOS 視窗確認…" }
        if selected == .accessibility { return "前往開啟輔助使用" }
        return status == .notDetermined ? "允許\(selected.title)" : "前往開啟\(selected.title)"
    }

    @ViewBuilder private var instructions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if selected == .accessibility {
                instruction(1, "按「前往開啟輔助使用」，進入系統設定。")
                instruction(2, "在「隱私權與安全性 → 輔助使用」找到 Hyday Talk，將旁邊的開關打開。")
                instruction(3, "若 macOS 要求驗證，請使用 Touch ID 或登入密碼，完成後返回 Hyday Talk。")
            } else if status == .denied || status == .granted || status == .restricted {
                instruction(1, "按「開啟\(selected.title)設定」，進入系統設定。")
                instruction(2, "在「隱私權與安全性 → \(selected.title)」找到 Hyday Talk，打開旁邊的開關。")
                instruction(3, "回到 Hyday Talk，確認這一步顯示「已開啟」。")
            } else {
                instruction(1, "按下方的「允許\(selected.title)」。")
                instruction(2, "macOS 出現 Hyday Talk 的授權視窗時，選擇「允許」。")
                instruction(3, "看到「已開啟」後，按「下一步」。")
            }
        }.padding(.horizontal, 16).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 12) {
            if selected == .accessibility {
                Text("若清單沒有 Hyday Talk，請按「＋」加入目前的 App 並開啟授權。")
                Button("在 Finder 顯示 Hyday Talk") { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
                    .buttonStyle(AlignButtonStyle())
                Text("可在選擇 App 的視窗按 ⌘⇧G，再貼上下方路徑。")
                HStack {
                    Text(Bundle.main.bundleURL.path).font(Typography.font(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(3)
                    Spacer(minLength: 0)
                    Button("複製路徑") { TextInsertion.copy(Bundle.main.bundleURL.path) }.buttonStyle(AlignButtonStyle()).controlSize(.regular)
                }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                Text("若系統開關已開啟但仍未授權，請移除舊項目，再加入上述路徑的 Hyday Talk 並開啟。")
                Text("設定後返回 Hyday Talk 並按「重新檢查」，若仍未生效，請按「稍後設定」後完全結束 App，再重新開啟。")
            } else {
                Text("如果之前按過「不允許」，macOS 通常不會再次跳出授權視窗。按「開啟\(selected.title)設定」，手動開啟 Hyday Talk。")
                Text("如果清單沒有 Hyday Talk，先回到這一步按「允許\(selected.title)」，讓 App 向 macOS 請求授權，再檢查清單。")
            }
            Text("macOS 若要求結束並重新開啟 App，請照提示操作。重新開啟後，可從「一般設定 → 查看設定指引」繼續。")
        }.font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        VStack(spacing: 0) {
            if number > 1 { Divider() }
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)").font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.muted).monospacedDigit()
                    .frame(width: 22, height: 22).background(Palette.subtleSurface, in: Circle())
                Text(text).font(Typography.font(.caption)).lineSpacing(Typography.paragraphSpacing).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 2)
            }.padding(.vertical, 12)
        }
    }
    private func requestSelectedPermission() {
        switch selected {
        case .microphone: model.grantMicrophone()
        case .speech: model.grantSpeech()
        case .accessibility: model.grantAccessibility()
        }
    }
}
