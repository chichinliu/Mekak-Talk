import SwiftUI
import TalkCore

struct LocalTextSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var models: [String] = []
    @State private var checking = false
    @State private var issue = ""

    private var selection: Binding<String> {
        Binding(get: { model.settings.localTextModel ?? "" }, set: { model.settings.localTextModel = $0.isEmpty ? nil : $0 })
    }

    private var modelOptions: [String] {
        var options = [""]
        if let selected = model.settings.localTextModel, !selected.isEmpty, !models.contains(selected) { options.append(selected) }
        return options + models
    }

    var body: some View {
        SettingsGroup(title: "本機文字 AI", detail: "使用本機模型補上標點、整理句子，並依內容呈現段落或列表。") {
            SettingsRow(title: "本機文字模型", detail: issue.isEmpty
                        ? (checking ? "正在檢查本機模型" : (models.isEmpty ? nil : "已偵測到本機文字模型"))
                        : issue) {
                HStack(spacing: 8) {
                    AlignMenuPicker(title: "本機文字模型", values: modelOptions, selection: selection,
                                    label: { $0.isEmpty ? "請選擇模型" : $0 }, showsTitle: false)
                        .frame(width: 200).disabled(checking || models.isEmpty)
                    Button("重新檢查") { Task { await refresh() } }.buttonStyle(AlignButtonStyle()).disabled(checking)
                }
            }
            if !issue.isEmpty {
                SettingsRow(title: "Ollama") {
                    Link("下載 Ollama", destination: URL(string: "https://ollama.com/download")!).font(Typography.font(.caption)).pointingCursor()
                }
            }
            SettingsBlock {
                Text("使用這台 Mac 已安裝的 Ollama 模型處理文字，逐字稿不會上傳。")
                    .font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            }
        }.task { await refresh() }
    }

    @MainActor private func refresh() async {
        guard !checking else { return }; checking = true; issue = ""
        defer { checking = false }
        do {
            let available = try await LocalTextClient.models()
            try Task.checkCancellation(); models = available
            if available.isEmpty { issue = "未偵測到文字模型，請先在 Ollama 下載模型後重新檢查。" }
            else if !available.contains(model.settings.localTextModel ?? "") {
                model.settings.localTextModel = available.contains("gemma3:4b") ? "gemma3:4b" : available.first
            }
        } catch is CancellationError { }
        catch { models = []; issue = "無法連接本機文字服務，請啟動 Ollama 後重新檢查。" }
    }
}
