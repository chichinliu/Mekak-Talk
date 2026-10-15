import SwiftUI
import TalkCore

// Home-specific surface variants keep the native Align controls and shared palette.
struct HomeVoiceKeycap: View {
    var recording = false
    var body: some View {
        Text("fn").font(Typography.font(.brand, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.accentInk)
            .frame(width: 50, height: 50)
            .background(LinearGradient(colors: [Palette.surface, recording ? Palette.accentSurface : Palette.card], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accentBorder, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.accentBorder).offset(y: 3))
            .shadow(color: Palette.accent.opacity(0.25), radius: 6, y: 4)
            .accessibilityElement(children: .ignore).accessibilityLabel("fn 快捷鍵")
    }
}

struct HomeOutputComparison: View {
    let input: String
    let output: String
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                legend("說話內容", color: Palette.faint, ink: Palette.muted, hatched: true)
                Text(input).font(Typography.font(.body)).foregroundStyle(Palette.muted).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .background(Palette.workspace, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 8) {
                legend("整理結果", color: Palette.action, ink: Palette.actionInk)
                Text(output).font(Typography.font(.body, weight: .medium)).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
                .accessibilityElement(children: .combine)
        }
    }
    private func legend(_ title: String, color: Color, ink: Color, hatched: Bool = false) -> some View {
        HStack(spacing: 6) {
            Group {
                if hatched { HatchedShape(color: Palette.actionBorder, line: Palette.action.opacity(0.5)) }
                else { color }
            }.frame(width: 12, height: 6).clipShape(Capsule()).accessibilityHidden(true)
            Text(title).font(Typography.font(.caption, weight: .medium)).foregroundStyle(ink)
        }
    }
}

struct HomeSettingButton: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = Palette.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(IconToken.font(.small, weight: .regular))
                    .foregroundStyle(Palette.muted).frame(width: 28, height: 28)
                    .background(Palette.subtleSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Typography.font(.caption)).foregroundStyle(Palette.muted)
                    Text(value).font(Typography.font(.body, weight: .medium)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(IconToken.font(.small, weight: .medium))
                    .foregroundStyle(Palette.muted).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(AlignNavigationStyle(horizontalPadding: 0))
            .homeKeyboardActivation(action)
            .accessibilityLabel("\(title)，\(value)").help("調整\(title)設定")
    }
}

struct HomeStatsCard: View {
    let stats: DictationStats
    let insights: UsageInsights
    let openInsights: () -> Void
    private let dayLabels: [String] = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_TW"); formatter.dateFormat = "EEEEE"
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).map { formatter.string(from: Calendar.current.date(byAdding: .day, value: $0 - 6, to: today)!) }
    }()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionTitle("使用統計", symbol: "chart.bar")
                Spacer(minLength: 8)
                Button("查看洞察", action: openInsights).buttonStyle(AlignButtonStyle(kind: .ghost))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(stats.todayWords)").font(.system(size: 44, weight: .light)).monospacedDigit()
                    .tracking(-1.5).contentTransition(.numericText())
                Text("今天用了 \(stats.todayCount) 次的語音輸入").font(Typography.font(.caption)).foregroundStyle(Palette.muted)
            }
            chart
            VStack(spacing: 0) {
                row("近 7 日字詞", "\(stats.weekWords)")
                Divider()
                row("近 7 日錄音", String(format: "%.1f 分鐘", stats.weekMinutes))
                Divider()
                row("平均每分鐘", stats.wordsPerMinute.map { "\($0) 字" } ?? "尚無資料")
            }
            if !stats.topDestinations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("常用 App").font(Typography.font(.caption, weight: .medium)).foregroundStyle(Palette.muted)
                    let top = stats.topDestinations.first?.count ?? 1
                    ForEach(stats.topDestinations, id: \.name) { item in
                        HStack(spacing: 10) {
                            Text(item.name).font(Typography.font(.caption)).lineLimit(1).truncationMode(.middle).frame(width: 96, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule().fill(Palette.subtleSurface).overlay(alignment: .leading) {
                                    Capsule().fill(Palette.action).frame(width: max(6, proxy.size.width * CGFloat(item.count) / CGFloat(top)))
                                }
                            }.frame(height: 6)
                            Text("\(item.count)").font(Typography.font(.caption, weight: .medium)).monospacedDigit().frame(width: 28, alignment: .trailing)
                        }
                    }
                }
            }
        }.frame(maxHeight: .infinity, alignment: .top).surface()
    }
    private var chart: some View {
        let peak = max(1, stats.dailyWords.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(stats.dailyWords.enumerated()), id: \.offset) { index, words in
                VStack(spacing: 6) {
                    if index == 6 {
                        Text("\(words)").font(Typography.font(.caption, weight: .medium)).monospacedDigit()
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Palette.surface, in: Capsule()).shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)
                            .fixedSize()
                    } else if words > 0 {
                        Text("\(words)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
                            .fixedSize()
                    }
                    Group {
                        if index == 6 { Palette.action }
                        else { HatchedShape(color: Palette.actionSurface, line: Palette.action.opacity(0.45)) }
                    }.frame(height: max(4, 64 * CGFloat(words) / CGFloat(peak)))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    Text(dayLabels[index]).font(Typography.font(.caption)).foregroundStyle(index == 6 ? Palette.ink : Palette.muted)
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 116, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("近 7 日字詞")
            .accessibilityValue(stats.dailyWords.map(String.init).joined(separator: "、"))
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).foregroundStyle(Palette.ink).monospacedDigit()
        }.font(Typography.font(.caption)).padding(.vertical, 10)
    }
}

private struct HomeKeyboardActivation: ViewModifier {
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.focusable(enabled)
            .onKeyPress(keys: [.return, .space], phases: .down) { key in
                guard enabled, key.modifiers.isEmpty else { return .ignored }
                action()
                return .handled
            }
    }
}

extension View {
    func homeKeyboardActivation(_ action: @escaping () -> Void) -> some View {
        modifier(HomeKeyboardActivation(action: action))
    }
}
