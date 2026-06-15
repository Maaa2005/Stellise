//
//  DesignSystem.swift
//  Stellise
//
//  リデザイン設計図（docs/redesign/design-direction.md）P0: カラー/トーン刷新の基盤。
//  色・タイポ・角丸・ガラスを一元化し、全画面で同じトークンを参照する。
//  ※トークン値は叩き台。微調整はこのファイルの定数を書き換えるだけで全画面に反映される。
//

import SwiftUI

// MARK: - Color(hex:) 初期化

/// アクセント（ラベンダーパープル）。旧来の `.blue` アクセントの置き換え先。
/// ShapeStyle 拡張にすることで `.foregroundStyle(.appAccent)` も `Color.appAccent` も両方使える。
extension ShapeStyle where Self == Color {
    static var appAccent: Color { Theme.Palette.accent }
    static var appAccentDeep: Color { Theme.Palette.accentDeep }
}

extension Color {
    /// "#1B1B3A" や "1B1B3A" 形式の16進文字列から Color を生成する。
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let r, g, b, a: Double
        switch cleaned.count {
        case 6: // RRGGBB
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8: // RRGGBBAA
            r = Double((value & 0xFF00_0000) >> 24) / 255
            g = Double((value & 0x00FF_0000) >> 16) / 255
            b = Double((value & 0x0000_FF00) >> 8) / 255
            a = Double(value & 0x0000_00FF) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - デザイントークン

/// アプリ全体で参照するデザイントークン。色はすべてここ経由で使う（直書き Color.blue 等を置き換える）。
enum Theme {

    // MARK: 色トークン

    enum Palette {
        // ベース・夜（紺→ほぼ黒の縦グラデ）
        static let nightTop = Color(hex: "#1B1B3A")     // 深い紺
        static let nightBottom = Color(hex: "#0A0A14")  // ほぼ黒

        // アクセント（ラベンダーパープル）
        static let accent = Color(hex: "#8B7CF6")       // メインCTA・リング・中央＋ボタン
        static let accentLight = Color(hex: "#B4A9FF")
        static let accentDeep = Color(hex: "#6C5CE0")

        // セマンティック
        static let warning = Color(hex: "#FF6B6B")      // 遅延・警告（赤は遅延時のみ）
        static let textOnDark = Color.white
        static let textOnDarkMuted = Color.white.opacity(0.8)
        static let textOnBright = Color(hex: "#1B1B3A") // 明背景（晴れ等）は濃紺文字
    }

    // MARK: 角丸

    enum Radius {
        static let card: CGFloat = 28
        static let small: CGFloat = 16
        // ピル/ボタンは Capsule() を使う
    }

    // MARK: 余白

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: タイポグラフィ

    enum Typography {
        /// 大時計（夜・朝共通）。weight と色は呼び出し側で背景に応じて切り替える。
        static func clock(_ size: CGFloat = 92) -> Font {
            .system(size: size, weight: .thin, design: .rounded).monospacedDigit()
        }

        static let titleEmphasis = Font.title.weight(.semibold)
        static let sectionTitle = Font.title2.weight(.semibold)
    }
}

// MARK: - 天気コンディション → 背景グラデ

/// 設計図 §4-1。AppState の背景状態から導出し、画面背景のグラデを決める。
enum WeatherCondition {
    case clear, cloudy, rain, snow, dawn, dusk, night

    /// 上→下の背景グラデーション（§2 パレット）。「紺を暗くした」上品なトーンを保つ。
    var gradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var gradientColors: [Color] {
        switch self {
        // iOS天気アプリ朝の空イメージ。上=澄んだ青→下=地平の淡い光。明るくリアルに。
        case .clear:  return [Color(hex: "#3B86E0"), Color(hex: "#79B8F2"), Color(hex: "#D6EEFC")]
        case .cloudy: return [Color(hex: "#4C5468"), Color(hex: "#8E99AE")]
        case .rain:   return [Color(hex: "#33405A"), Color(hex: "#5E6B86")]
        // 早朝: 夕方と同じ暖色トーン。上=藍 → 中=紫 → 下=朝焼けのピーチ。
        case .dawn:   return [Color(hex: "#262049"), Color(hex: "#6E4A78"), Color(hex: "#E8A878")]
        // 夕暮れ: 上=藍 → 中=マゼンタ → 下=夕焼けのオレンジ
        case .dusk:   return [Color(hex: "#262049"), Color(hex: "#6E4A78"), Color(hex: "#D08A66")]
        case .snow:   return [Color(hex: "#5A6B86"), Color(hex: "#C2CCE0")]
        case .night:  return [Theme.Palette.nightTop, Theme.Palette.nightBottom]
        }
    }

    /// 明るい背景（晴れ・曇り・雪）か。テキスト色の切り替えに使う。
    var isBright: Bool {
        switch self {
        case .clear, .cloudy, .snow: return true
        case .rain, .dawn, .dusk, .night: return false
        }
    }

    /// AppState の `backgroundImageName` から導出（既存ロジックと整合）。
    static func from(backgroundImageName name: String) -> WeatherCondition {
        switch name {
        case "bg_sunny": return .clear
        case "bg_cloudy": return .cloudy
        case "bg_rainy": return .rain
        default: return .night
        }
    }
}

// MARK: - 夜の没入グラデ（NightView 用）

extension LinearGradient {
    /// 夜（NightView）の没入ダーク背景。紺→ほぼ黒。
    static let nightImmersive = LinearGradient(
        colors: [Theme.Palette.nightTop, Theme.Palette.nightBottom],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - ガラスカード（.ultraThinMaterial）

/// 設計図 §2。カードはガラス＋わずかな内側ハイライトで立体感を出す。
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.card

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

extension View {
    /// ガラス調カードの装飾を付与する。
    func glassCard(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
