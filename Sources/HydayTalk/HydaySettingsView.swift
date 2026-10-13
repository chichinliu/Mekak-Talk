import SwiftUI
import AppKit
import TalkCore

enum HydayBrand {
    /// Hyday's own icon from the installed app. Read from the bundle directly: looking it up by
    /// bundle ID can resolve to a development build that still carries a placeholder icon.
    static let icon: NSImage? = ["/Applications/Hyday.app", NSHomeDirectory() + "/Applications/Hyday.app"]
        .lazy.compactMap { NSImage(contentsOfFile: $0 + "/Contents/Resources/icon.icns") }.first
}

struct HydaySettingsView: View {
    @ObservedObject var model: AppModel
    private var root: URL? { model.hydayRoot }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Hyday 資料夾", detail: "Hyday Talk 會直接寫入此資料夾中的日誌，不需要開啟 Hyday。") {
                SettingsRow(title: root?.path ?? "尚未設定",
                            detail: model.settings.hydayFolder == nil
                                ? (root == nil ? "找不到 Hyday 的資料夾設定，請選擇 Hyday 筆記所在的資料夾。" : "沿用 Hyday 的資料夾設定。")
                                : "使用自行選擇的資料夾。") {
                    HStack(spacing: 8) {
                        if model.settings.hydayFolder != nil {
                            Button("沿用 Hyday 設定") { model.settings.hydayFolder = nil; model.reloadHydayVocabulary() }.buttonStyle(AlignButtonStyle())
                        }
                        Button("選擇資料夾") { chooseFolder() }.buttonStyle(AlignButtonStyle())
                    }
                }
            }
            SettingsGroup(title: "記到 Hyday", detail: "說完後依 Life Log 規則整理，第一行標上記錄時間，加在今天日誌的最後面；一般聽寫不會寫入 Hyday。") {
                SettingsRow(title: "快捷鍵", detail: root == nil ? "設定 Hyday 資料夾後才能使用。" : nil) {
                    HStack(spacing: 6) { Keycap("fn"); Text("+").foregroundStyle(Palette.muted); Keycap("Space") }
                }
            }
            SettingsGroup(title: "問筆記", detail: "使用提問時，先搜尋 Hyday 資料夾中的筆記，再根據找到的內容回答，並在最後附上參考筆記的連結。") {
                SettingsRow(title: "提問時參考 Hyday 筆記",
                            detail: root == nil ? "設定 Hyday 資料夾後才能使用。"
                                : model.settings.textBackend == .basic ? "需要在「文字整理」選擇本機 AI 或 API。"
                                : (HydaySearchService.installation() == nil ? "未安裝 Hyday，使用內建的關鍵字搜尋。" : "使用 Hyday 內建的搜尋，不需要開啟 Hyday 視窗。")) {
                    Toggle("提問時參考 Hyday 筆記", isOn: $model.settings.asksHydayNotes).labelsHidden()
                }
            }
            SettingsGroup(title: "Hyday 詞彙", detail: "讀取筆記中的 @(名稱) 與 #標籤，作為語音辨識的提示，不會加入個人辭典。") {
                SettingsRow(title: model.scanningHydayVocabulary ? "正在讀取…" : "已讀取 \(model.hydayVocabulary.count) 個詞彙",
                            detail: root == nil ? "設定 Hyday 資料夾後才能使用。" : "打開 Hyday Talk 時會自動讀取，筆記有新增名稱或標籤時可重新讀取。") {
                    Button("重新讀取") { model.reloadHydayVocabulary() }.buttonStyle(AlignButtonStyle())
                        .disabled(root == nil || model.scanningHydayVocabulary)
                }
            }
        }.disabled(model.phase.busy)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "選擇"; panel.message = "選擇 Hyday 筆記所在的資料夾"
        if let current = root { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url { model.settings.hydayFolder = url.path; model.reloadHydayVocabulary() }
    }
}
