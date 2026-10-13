import SwiftUI
import AppKit
import Speech
import TalkCore

/// Settings pages read best at a limited width: rows keep labels on the left and controls on the right.
private let settingsWidth: CGFloat = 760

struct SettingsGroup<Content: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Typography.font(.body, weight: .medium)).singleLineHeading()
                if let detail {
                    Text(detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
                }
            }.padding(.horizontal, 4)
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedLayout()) { content }
            }.padding(.horizontal, 18).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Surfaces.radius).strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 4)
        }.frame(maxWidth: settingsWidth, alignment: .leading)
    }
}

/// Puts a hairline between rows so a group reads as one list.
private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        ForEach(children) { child in
            child
            if child.id != children.last?.id { Divider().overlay(Palette.border) }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    var badge: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(Typography.font(.body))
                    if let badge {
                        Text(badge).font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.accentInk)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Palette.accentSurface, in: Capsule())
                    }
                }
                if let detail {
                    Text(detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                        .lineSpacing(Typography.paragraphSpacing).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            control
        }.padding(.vertical, 14).frame(minHeight: 52)
    }
}

/// Free-form content inside a group, such as a note, an example or a list.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typography.font(.caption)).foregroundStyle(Palette.muted).lineSpacing(Typography.paragraphSpacing)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 560, alignment: .leading)
    }
}

struct SpeechSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("辨識來源").font(Typography.font(.body, weight: .medium)).padding(.horizontal, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(SpeechBackend.availableSources) { backend in
                        let selected = model.settings.speechBackend == backend
                        Button { model.settings.speechBackend = backend } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: backend.symbol).font(IconToken.font(.small)).foregroundStyle(selected ? Palette.action : Palette.muted)
                                        .frame(width: 30, height: 30).background(selected ? Palette.actionSurface : Palette.subtleSurface, in: Circle())
                                    Spacer(minLength: 0)
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Palette.action : Palette.faint)
                                }
                                Text(backend.title).font(Typography.font(.body, weight: .medium)).singleLineHeading()
                                Text(backend.detail).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        }.buttonStyle(AlignChoiceStyle(selected: selected)).accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }.frame(maxWidth: settingsWidth)
            switch model.settings.speechBackend {
            case .system:
                SettingsGroup(title: "macOS 系統辨識", detail: "不需 API Key。部分語言可能由 Apple 伺服器處理音訊，單次錄音最多 55 秒。") {
                    let offline = SFSpeechRecognizer(locale: Locale(identifier: model.settings.locale))?.supportsOnDeviceRecognition == true
                    SettingsRow(title: "僅使用離線辨識",
                                detail: offline ? "目前語言支援系統離線辨識" : "目前語言的離線支援需由系統確認；不支援時會提示切換來源") {
                        Toggle("僅使用離線辨識", isOn: $model.settings.systemOfflineOnly).labelsHidden()
                    }
                    if !model.speechAllowed {
                        SettingsRow(title: "語音辨識權限") {
                            Button("設定語音辨識權限") { model.openPermissionGuide(at: .speech) }.buttonStyle(AlignButtonStyle())
                        }
                    }
                }
            case .whisper, .cli:
                LocalModelSettingsView(model: model, manager: model.localModels)
            case .api:
                SettingsGroup(title: "語音辨識 API", detail: "錄音會傳送至你設定的服務。支援 /audio/transcriptions；本機相容服務可不填 Key。") {
                    SettingsBlock { APISettingsFields(settings: $model.settings.speechAPI, account: "speech", model: model) }
                }
            }
            SettingsGroup(title: "語音辨識語言") {
                SettingsRow(title: "辨識語言", detail: "繁體中文會套用字形轉換、全形標點與個人辭典，中英混說的準確度取決於辨識來源。") {
                    AlignMenuPicker(title: "辨識語言", values: ["zh-TW", "en-US", "ja-JP", "zh-CN"], selection: $model.settings.locale,
                                    label: { ["zh-TW": "繁體中文 · 台灣", "en-US": "English · United States", "ja-JP": "日本語", "zh-CN": "简体中文"][$0] ?? $0 },
                                    showsTitle: false).frame(width: 220)
                }
            }
        }.disabled(model.phase.busy)
    }
}

struct TextSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "文字整理來源") {
                SettingsRow(title: "整理方式", detail: model.settings.textBackend == .basic
                            ? "保留辨識原文、轉換字形與既有標點並套用辭典，如需補上標點或整理列表，請選擇本機 AI 或 API Key。" : nil) {
                    AlignSegmentedPicker(title: "文字整理來源", values: TextBackend.availableSources,
                                         selection: $model.settings.textBackend, label: { $0.title }).frame(width: 300)
                }
            }
            switch model.settings.textBackend {
            case .basic: EmptyView()
            case .local, .cli:
                LocalTextSettingsView(model: model)
            case .api:
                SettingsGroup(title: "文字 AI API", detail: "逐字稿、個人辭典與提問時選取的文字會送至這個服務。支援 /chat/completions，也可連接本機模型服務。") {
                    SettingsBlock { APISettingsFields(settings: $model.settings.textAPI, account: "text", model: model) }
                }
            }
            SettingsGroup(title: "聽寫風格", detail: "設定會自動儲存，於下一次聽寫套用。") {
                SettingsRow(title: "風格", detail: model.settings.textBackend == .basic
                            ? "目前使用基礎整理，如需套用自然或正式風格，請選擇本機 AI 或 API Key。"
                            : model.settings.writingStyle.detail) {
                    AlignSegmentedPicker(title: "聽寫風格", values: WritingStyle.allCases,
                                         selection: $model.settings.writingStyle, label: { $0.title }).frame(width: 260)
                        .disabled(model.settings.textBackend == .basic)
                }
                if model.settings.textBackend != .basic {
                    SettingsBlock { ExamplePair(input: WritingStyle.exampleInput, output: model.settings.writingStyle.exampleOutput) }
                }
            }
            SettingsGroup(title: "翻譯目標語言", detail: "翻譯需要本機 AI 或 API Key，右 Shift 不會啟動翻譯。") {
                SettingsRow(title: "目標語言", detail: "按住左 Shift 並按 fn 開始翻譯，說完後再按 fn 完成。") {
                    AlignMenuPicker(title: "目標語言", values: ["英文", "台灣繁體中文", "日文", "韓文", "西班牙文"],
                                    selection: $model.settings.targetLanguage, label: { $0 }, showsTitle: false).frame(width: 200)
                }
            }
        }.disabled(model.phase.busy)
    }
}

struct DictionaryView: View {
    @ObservedObject var model: AppModel
    @State private var heard = ""
    @State private var replacement = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "新增詞彙", detail: "繁體中文模式請使用繁體字，辭典會套用至辨識結果並提供給系統辨識與文字 AI 作為提示。") {
                SettingsBlock {
                    HStack(alignment: .bottom, spacing: 12) {
                        LabeledField("辨識文字", placeholder: "例如：海帶", text: $heard)
                        Image(systemName: "arrow.right").foregroundStyle(Palette.muted).padding(.bottom, 11)
                        LabeledField("替換文字", placeholder: "例如：Hyday", text: $replacement)
                        Button("加入") {
                            model.settings.dictionary.append(DictionaryEntry(heard: heard.trimmingCharacters(in: .whitespacesAndNewlines), replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines)))
                            heard = ""; replacement = ""
                        }.buttonStyle(AlignButtonStyle(kind: .primary)).disabled(heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            SettingsGroup(title: "個人辭典", detail: "標示為自動加入的詞彙來自你對插入文字的修正，可於一般設定關閉此功能。新學到的詞彙標示為待確認，按下確認後才會套用。") {
                if model.settings.learnsFromCorrections {
                    SettingsRow(title: "最近一次比對結果",
                                detail: model.lastCorrectionCheck.map { "\($0.app) · \($0.date.formatted(date: .omitted, time: .shortened))" }
                                    ?? "聽寫插入文字後，修改再離開輸入框，這裡會顯示比對結果。") {
                        Text(model.lastCorrectionCheck?.message ?? "尚未比對")
                            .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.trailing).frame(maxWidth: 260, alignment: .trailing)
                    }
                    Divider()
                }
                if model.settings.dictionary.isEmpty {
                    SettingsBlock {
                        Label("尚無詞彙，請新增經常辨識錯誤的人名或術語。", systemImage: "character.book.closed")
                            .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    }
                } else {
                    HStack(spacing: 14) {
                        Text("辨識文字").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 14)
                        Text("替換文字").frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(width: 28)
                    }.font(Typography.font(.caption)).foregroundStyle(Palette.muted).padding(.vertical, 10)
                    ForEach(model.settings.dictionary) { entry in
                        HStack(spacing: 14) {
                            Text(entry.heard).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").font(IconToken.font(.small)).foregroundStyle(Palette.faint).frame(width: 14)
                            HStack(spacing: 8) {
                                Text(entry.replacement)
                                if entry.isPending {
                                    Text("待確認").font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.warningInk)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Palette.warningSurface, in: Capsule())
                                } else if entry.isAutomatic {
                                    Text("自動加入").font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.actionInk)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Palette.surface, in: Capsule()).shadow(color: Color.black.opacity(0.06), radius: 1.5, y: 1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if entry.isPending {
                                Button("確認") { DictionaryLearning.confirm(entry, in: &model.settings) }
                                    .buttonStyle(AlignButtonStyle(kind: .primary)).accessibilityLabel("確認詞彙 \(entry.heard)")
                            }
                            Button { DictionaryLearning.remove(entry, from: &model.settings) } label: { Image(systemName: "trash").frame(width: 20, height: 20) }
                                .buttonStyle(AlignButtonStyle(kind: .ghost)).help("刪除詞彙 \(entry.heard)").accessibilityLabel("刪除詞彙 \(entry.heard)")
                        }.font(Typography.font(.body)).padding(.vertical, 8)
                    }
                }
            }
        }.disabled(model.phase.busy)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PermissionsView(model: model).frame(maxWidth: settingsWidth)
            SettingsGroup(title: "快捷鍵", detail: "按一次 fn 開始，再按 fn 完成。如 fn 同時開啟表情符號或系統聽寫，請在系統設定 → 鍵盤，將「按下 🌐 鍵來」設為「不執行動作」。") {
                ForEach(VoiceAction.allCases) { action in
                    SettingsRow(title: action.title) { Keycap(action.shortcut) }
                }
                SettingsRow(title: "取消錄音 / 處理") { Keycap("esc") }
                SettingsRow(title: "鍵盤設定") {
                    Button("開啟鍵盤設定") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
                    }.buttonStyle(AlignButtonStyle())
                }
            }
            SettingsGroup(title: "輸入與紀錄", detail: "本機模型與 API 使用的暫存音訊會在完成或取消後刪除，系統辨識不寫入音訊檔，API Key 儲存在 macOS 鑰匙圈。") {
                SettingsRow(title: "聽寫與翻譯完成後，自動插入原本的文字框",
                            detail: model.settings.autoInsert ? "未偵測到輸入框或輸入位置已變更時，自動複製文字。" : nil) {
                    Toggle("聽寫與翻譯完成後，自動插入原本的文字框", isOn: $model.settings.autoInsert).labelsHidden()
                }
                SettingsRow(title: "從修改內容自動學習詞彙",
                            detail: "插入文字後，Hyday Talk 會讀取該輸入框的內容並與插入文字比對，僅將修正過的詞彙加入個人辭典，不保存其他內容。") {
                    Toggle("從修改內容自動學習詞彙", isOn: $model.settings.learnsFromCorrections).labelsHidden()
                }
                SettingsRow(title: "在這台 Mac 保留文字紀錄") {
                    Toggle("在這台 Mac 保留文字紀錄", isOn: $model.settings.saveHistory).labelsHidden()
                }
                SettingsRow(title: "播放開始與完成提示音") {
                    Toggle("播放開始與完成提示音", isOn: $model.settings.interactionSounds).labelsHidden()
                }
                SettingsRow(title: "我的打字速度", detail: "用於估算洞察頁的節省時間，台灣常見的注音打字速度約為每分鐘 20 至 50 字。") {
                    Stepper(value: $model.settings.typingWordsPerMinute, in: 10...200, step: 5) {
                        Text("每分鐘 \(model.settings.typingWordsPerMinute) 字").monospacedDigit()
                    }.fixedSize()
                }
            }.disabled(model.phase.busy)
            SettingsGroup(title: "Hyday Talk 0.1.0") {
                SettingsBlock { Note("支援 macOS 14 以上及系統預設麥克風，提供聽寫、翻譯與文字提問功能，提問不包含網路搜尋或外部操作。") }
            }
        }
    }
}

struct APISettingsFields: View {
    @Binding var settings: APISettings
    let account: String
    @ObservedObject var model: AppModel
    @State private var key = ""
    @State private var saved = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledField("服務基底網址", placeholder: "https://api.openai.com/v1", text: $settings.baseURL, monospaced: true)
            LabeledField("模型名稱", placeholder: "服務提供的模型名稱", text: $settings.model, monospaced: true)
            VStack(alignment: .leading, spacing: 7) {
                Text("API Key").font(Typography.font(.caption, weight: .medium))
                HStack {
                    SecureField("API Key", text: $key, prompt: Text("sk-…（本機服務可留白）").foregroundStyle(Palette.muted))
                        .textFieldStyle(AlignTextFieldStyle()).accessibilityLabel("API Key")
                        .onChange(of: key) { _, _ in saved = false }
                    Button("儲存 Key") {
                        do {
                            let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !value.contains("\n"), !value.contains("\r") else { throw TalkError("API Key 不可包含換行，請重新貼上。") }
                            try KeyStore.write(value, account: account); saved = true
                            model.notice = value.isEmpty ? "已清除 API Key。" : "API Key 已存入 macOS 鑰匙圈。"
                        } catch { model.report(error) }
                    }.buttonStyle(AlignButtonStyle())
                }
                if saved { Label(key.isEmpty ? "未設定 Key" : "已儲存至鑰匙圈", systemImage: "lock").font(Typography.font(.caption)).foregroundStyle(Palette.action) }
            }
        }.onAppear { key = KeyStore.read(account); saved = !key.isEmpty }
    }
}

struct FilePathField: View {
    let title: String
    @Binding var path: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Typography.font(.caption, weight: .medium))
            HStack {
                TextField(title, text: $path, prompt: Text("/完整/檔案路徑").foregroundStyle(Palette.muted))
                    .textFieldStyle(AlignTextFieldStyle(monospaced: true)).accessibilityLabel(title)
                Button("選擇檔案") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                    panel.message = "選擇\(title)"
                    if panel.runModal() == .OK, let url = panel.url { path = url.path }
                }.buttonStyle(AlignButtonStyle())
            }
        }
    }
}

struct LabeledField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var monospaced = false
    init(_ title: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) {
        self.title = title; self.placeholder = placeholder; _text = text; self.monospaced = monospaced
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Typography.font(.caption, weight: .medium))
            TextField(title, text: $text, prompt: Text(placeholder).foregroundStyle(Palette.muted))
                .textFieldStyle(AlignTextFieldStyle(monospaced: monospaced)).accessibilityLabel(title)
        }
    }
}

struct SectionTitle: View {
    let title: String
    let symbol: String
    init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    /// Each section keeps its own hue so titles are told apart at a glance.
    private var tint: Color {
        switch symbol {
        case "chart.bar": return Palette.action
        case "keyboard": return Palette.ai
        case "slider.horizontal.3": return Palette.success
        case "text.alignleft": return Palette.accent
        case "text.bubble": return Palette.warning
        default: return Palette.muted
        }
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(IconToken.font(.regular, weight: .regular))
                .foregroundStyle(tint).frame(width: 20)
                .accessibilityHidden(true)
            Text(title).font(Typography.font(.section, weight: .medium)).foregroundStyle(Palette.ink).singleLineHeading()
        }
    }
}
