import SwiftUI

/// 起動時のローディング画面。Stelliseのアイコン世界観（紺〜紫の夜空＋月/星）に合わせ、
/// 太陽が地平から昇る「日の出」アニメーション。星が薄れ、暖色の夜明けが差し、
/// 中央に光が満ちて Stellise のワードマークが現れる。すべて手続き描画でアセット不要。
struct LoadingView: View {
    @State private var risen = false     // 太陽の上昇（日の出）
    @State private var pulse = false     // グロウのゆるい呼吸
    @State private var appear = false    // ワードマークのフェードイン

    // 星の固定配置（x割合, y割合, サイズ）。空の上半分に散らす。
    private let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.18, 0.12, 2.0), (0.32, 0.20, 1.4), (0.5, 0.10, 2.6), (0.68, 0.16, 1.6),
        (0.82, 0.22, 2.0), (0.26, 0.30, 1.2), (0.74, 0.30, 1.4), (0.44, 0.26, 1.8),
        (0.6, 0.24, 1.2), (0.12, 0.24, 1.4), (0.88, 0.13, 1.6), (0.38, 0.15, 1.2),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 夜明けの空（上＝紺、下＝紫）
                LinearGradient(
                    colors: [Color(hex: "#14142C"), Color(hex: "#241E46"), Color(hex: "#3E3163")],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                // 太陽が昇るほど下部に差す暖色の夜明け光
                LinearGradient(
                    colors: [
                        .clear,
                        Color(hex: "#9B6FC8").opacity(risen ? 0.30 : 0.0),
                        Color(hex: "#F0A968").opacity(risen ? 0.55 : 0.0),
                    ],
                    startPoint: .center, endPoint: .bottom
                )
                .ignoresSafeArea()

                // 星（昇ると薄れる）
                ForEach(stars.indices, id: \.self) { i in
                    let s = stars[i]
                    Circle()
                        .fill(.white)
                        .frame(width: s.2, height: s.2)
                        .opacity((risen ? 0.18 : 0.9) * (pulse ? 1.0 : 0.55))
                        .position(x: s.0 * w, y: s.1 * h)
                }

                // 太陽＋グロウ（地平の下から中央上へ昇る）
                ZStack {
                    // 広い暖色グロウ（呼吸でわずかに伸縮）
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color(hex: "#FFE8B0"), Color(hex: "#FFB873").opacity(0.45), .clear],
                            center: .center, startRadius: 4, endRadius: 170))
                        .frame(width: 360, height: 360)
                        .scaleEffect(pulse ? 1.06 : 0.92)
                        .blur(radius: 6)
                    // 太陽本体
                    Circle()
                        .fill(RadialGradient(
                            colors: [.white, Color(hex: "#FFDF9C")],
                            center: .center, startRadius: 0, endRadius: 48))
                        .frame(width: 96, height: 96)
                }
                .position(x: w * 0.5, y: risen ? h * 0.4 : h * 0.92)
                .opacity(risen ? 1 : 0.85)

                // ワードマーク
                VStack(spacing: 8) {
                    Spacer()
                    Text("Stellise")
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .tracking(8)
                        .foregroundStyle(.white)
                        .opacity(appear ? 0.95 : 0)
                        .offset(y: appear ? 0 : 14)
                    Text("おはよう、今日を始めよう")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.65))
                        .opacity(appear ? 1 : 0)
                        .padding(.bottom, h * 0.12)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.7)) { risen = true }
                withAnimation(.easeIn(duration: 0.9).delay(0.6)) { appear = true }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        .ignoresSafeArea()
    }
}

// プレビュー用
struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
    }
}
