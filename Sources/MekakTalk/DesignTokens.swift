import SwiftUI

enum DesignTokens {
    enum Colors {
        static let voiceSurface = Color(.sRGB, red: 244 / 255, green: 245 / 255, blue: 247 / 255) // #F4F5F7
        static let canvas = Color(.sRGB, red: 254 / 255, green: 254 / 255, blue: 254 / 255) // #FEFEFE
        static let workspace = Color(.sRGB, red: 243 / 255, green: 245 / 255, blue: 249 / 255) // #F3F5F9
        static let sidebar = Color(.sRGB, red: 243 / 255, green: 245 / 255, blue: 249 / 255) // #F3F5F9
        static let card = Color(.sRGB, red: 252 / 255, green: 252 / 255, blue: 252 / 255) // #FCFCFC
        static let subtleSurface = Color(.sRGB, red: 236 / 255, green: 235 / 255, blue: 236 / 255) // #ECEBEC
        static let accent = Color(.sRGB, red: 30 / 255, green: 75 / 255, blue: 153 / 255) // #1E4B99
        static let accentInk = Color(.sRGB, red: 22 / 255, green: 58 / 255, blue: 122 / 255) // #163A7A
        static let accentSurface = Color(.sRGB, red: 232 / 255, green: 238 / 255, blue: 248 / 255) // #E8EEF8
        static let accentBorder = Color(.sRGB, red: 197 / 255, green: 211 / 255, blue: 236 / 255) // #C5D3EC
        static let action = Color(.sRGB, red: 46 / 255, green: 107 / 255, blue: 240 / 255) // #2E6BF0
        static let actionInk = Color(.sRGB, red: 36 / 255, green: 83 / 255, blue: 194 / 255) // #2453C2
        static let actionSurface = Color(.sRGB, red: 238 / 255, green: 243 / 255, blue: 255 / 255) // #EEF3FF
        static let actionBorder = Color(.sRGB, red: 217 / 255, green: 228 / 255, blue: 253 / 255) // #D9E4FD
        static let ai = Color(.sRGB, red: 122 / 255, green: 90 / 255, blue: 248 / 255) // #7A5AF8
        static let aiSurface = Color(.sRGB, red: 243 / 255, green: 240 / 255, blue: 255 / 255) // #F3F0FF
        static let ink = Color(.sRGB, red: 17 / 255, green: 28 / 255, blue: 52 / 255) // #111C34
        static let selectedSurface = Color(.sRGB, red: 255 / 255, green: 255 / 255, blue: 255 / 255) // #FFFFFF
        static let muted = Color(.sRGB, red: 106 / 255, green: 111 / 255, blue: 120 / 255) // #6A6F78
        static let faint = Color(.sRGB, red: 163 / 255, green: 168 / 255, blue: 177 / 255) // #A3A8B1
        static let border = Color(.sRGB, red: 227 / 255, green: 229 / 255, blue: 233 / 255) // #E3E5E9
        static let success = Color(.sRGB, red: 31 / 255, green: 157 / 255, blue: 98 / 255) // #1F9D62
        static let successInk = Color(.sRGB, red: 21 / 255, green: 112 / 255, blue: 72 / 255) // #157048
        static let successSurface = Color(.sRGB, red: 232 / 255, green: 247 / 255, blue: 239 / 255) // #E8F7EF
        static let successBorder = Color(.sRGB, red: 205 / 255, green: 235 / 255, blue: 219 / 255) // #CDEBDB
        static let warning = Color(.sRGB, red: 229 / 255, green: 162 / 255, blue: 58 / 255) // #E5A23A
        static let warningInk = Color(.sRGB, red: 138 / 255, green: 90 / 255, blue: 18 / 255) // #8A5A12
        static let warningSurface = Color(.sRGB, red: 255 / 255, green: 248 / 255, blue: 236 / 255) // #FFF8EC
        static let warningBorder = Color(.sRGB, red: 246 / 255, green: 227 / 255, blue: 191 / 255) // #F6E3BF
        static let danger = Color(.sRGB, red: 207 / 255, green: 48 / 255, blue: 42 / 255) // #CF302A
        static let dangerSurface = Color(.sRGB, red: 255 / 255, green: 239 / 255, blue: 235 / 255) // #FFEFEB
        static let onAccent = Color.white
        static let onAction = Color.white
        static let surface = Color.white
        static let separator = border
        static let shadow = Color.black.opacity(0.06)
    }

    enum Typography {
        // Native macOS sizes use points: 13 pt is 13 logical UI pixels, independent of Retina scale.
        // Every informative label, button, field, timer, shortcut, and error uses this floor.
        static let minimumSize: CGFloat = 13
        enum Role {
            case caption, body, section, brand, cardTitle, title, pageTitle, display, metric
            fileprivate var size: CGFloat {
                switch self {
                case .caption: return 13
                case .body: return 14
                case .section: return 16
                case .brand: return 18
                case .cardTitle: return 20
                case .title, .metric: return 24
                case .pageTitle: return 26
                case .display: return 40
                }
            }
        }
        static func pointSize(_ role: Role) -> CGFloat { max(minimumSize, role.size) }
        static func font(_ role: Role, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
            .system(size: pointSize(role), weight: weight, design: design)
        }
        static let paragraphSpacing: CGFloat = 3
    }

    enum Icons {
        enum Size: CGFloat { case small = 13, regular = 16, badge = 20, large = 24, prominent = 28, emptyState = 36 }
        static func font(_ size: Size, weight: Font.Weight = .regular) -> Font {
            .system(size: size.rawValue, weight: weight)
        }
    }

    enum Surfaces {
        static let padding: CGFloat = 20
        static let radius: CGFloat = 20
        static let controlRadius: CGFloat = 8
        static let sectionGap: CGFloat = 24
        static let border = Color.black.opacity(0.065)
        static let contactShadow = Color.black.opacity(0.035)
        static let ambientShadow = Color.black.opacity(0.025)
    }

    /// The mark: seven waveform bars whose silhouette reads as an M, drawn in a 100 × 100 box centred on y = 50.
    enum Logo {
        static let bars: [(x: CGFloat, height: CGFloat, width: CGFloat)] = [
            (14, 40, 8), (26, 86, 8), (38, 60, 8), (50, 24, 8), (62, 60, 8), (74, 86, 8), (86, 40, 8),
        ]
    }

    enum Layout {
        static let guideWidth: CGFloat = 860
        static let guideHeight: CGFloat = 680
        static let voicePanelWidth: CGFloat = 256
        static let voicePanelHeight: CGFloat = 52
        static let voiceDetailHeight: CGFloat = 200
        static let voicePanelPadding: CGFloat = 8
        static let voicePanelBottomInset: CGFloat = 24
        static let voiceControlSize: CGFloat = 28
    }
}

typealias Palette = DesignTokens.Colors
typealias Typography = DesignTokens.Typography
typealias IconToken = DesignTokens.Icons
typealias LayoutToken = DesignTokens.Layout

/// The Mekak Talk mark on its blue tile.
struct MekakLogo: View {
    var size: CGFloat = 28
    var body: some View {
        Canvas { context, canvas in
            let unit = canvas.width * 0.72 / 100, inset = canvas.width * 0.14
            for bar in DesignTokens.Logo.bars {
                let rect = CGRect(x: inset + (bar.x - bar.width / 2) * unit, y: inset + (50 - bar.height / 2) * unit,
                                  width: bar.width * unit, height: bar.height * unit)
                context.fill(Path(roundedRect: rect, cornerRadius: bar.width * unit / 2), with: .color(Palette.onAccent))
            }
        }
        .frame(width: size, height: size)
        .background(Palette.accent, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }
}
