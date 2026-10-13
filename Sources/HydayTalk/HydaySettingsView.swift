import SwiftUI
import AppKit
import TalkCore

enum HydayBrand {
    /// Hyday's own app icon when Hyday is installed.
    static let icon: NSImage? = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hyday.app")
        .flatMap { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? ["/Applications/Hyday.app", NSHomeDirectory() + "/Applications/Hyday.app"]
            .first { FileManager.default.fileExists(atPath: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0) }
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
                            Button("沿用 Hyday 設定") { model.settings.hydayFolder = nil }.buttonStyle(AlignButtonStyle())
                        }
                        Button("選擇資料夾") { chooseFolder() }.buttonStyle(AlignButtonStyle())
                    }
                }
            }
            SettingsGroup(title: "記到 Hyday", detail: "說完後整理成一個列點，加在今天日誌的最後面；一般聽寫不會寫入 Hyday。") {
                SettingsRow(title: "快捷鍵", detail: root == nil ? "設定 Hyday 資料夾後才能使用。" : nil) {
                    HStack(spacing: 6) { Keycap("fn"); Text("+").foregroundStyle(Palette.muted); Keycap("Space") }
                }
            }
        }.disabled(model.phase.busy)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "選擇"; panel.message = "選擇 Hyday 筆記所在的資料夾"
        if let current = root { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url { model.settings.hydayFolder = url.path }
    }
}
