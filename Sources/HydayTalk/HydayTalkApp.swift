import SwiftUI
import AppKit
import TalkCore

@main
struct HydayTalkApp: App {
    @NSApplicationDelegateAdaptor(TalkAppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared
    var body: some Scene {
        Window("Hyday Talk", id: "main") {
            MainWindowContent(model: model)
        }.defaultSize(width: 1060, height: 780).windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .newItem) {}
                AboutCommands()
            }
        Window("關於 Hyday Talk", id: "about") {
            AboutView()
        }.windowResizability(.contentSize)
        MenuBarExtra {
            MenuContent(model: model).font(Typography.font(.body))
        } label: {
            Image(systemName: model.phase == .recording ? "mic.fill" : "waveform")
                .accessibilityLabel(model.phase == .recording ? "Hyday Talk 正在錄音" : "Hyday Talk")
        }
    }
}

private struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("關於 Hyday Talk") { openWindow(id: "about") }
        }
    }
}

private struct AboutView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    var body: some View {
        VStack(spacing: 16) {
            HydayLogo(size: 64)
            Text("Hyday Talk").font(Typography.font(.title, weight: .semibold)).singleLineHeading()
            Text("支援聽寫、翻譯與文字提問。").font(Typography.font(.body))
            Text("版本 \(version) · macOS 原生版").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
        }.padding(32).frame(width: 400, height: 260).background(Palette.canvas)
            .font(Typography.font(.body)).foregroundStyle(Palette.ink).preferredColorScheme(.light)
    }
}

private struct MainWindowContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MainView(model: model).onAppear {
            model.showWindow = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.phase.title)
        if model.phase == .recording { Button("完成錄音 · fn") { model.finish() } }
        else if !model.phase.busy {
            Button("開始聽寫 · fn") { model.begin() }
            Button("開始翻譯 · fn + 左 ⇧") { model.begin(action: .translate) }
            Button("開始提問 · fn + Control") { model.begin(action: .ask) }
        }
        if model.phase.busy { Button("取消 · esc") { model.cancel() } }
        if !model.result.isEmpty { Button("複製最近結果") { model.copyResult() } }
        Divider()
        Button("開啟 Hyday Talk") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Text("辨識：\(model.settings.speechBackend.title)")
        Divider()
        Button("結束 Hyday Talk") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@MainActor
final class TalkAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: VoicePanel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        let panel = VoicePanel(model: model); self.panel = panel
        model.onPanelChange = { [weak panel] in panel?.refresh() }
        model.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.showWindow?(); return true
    }
}
