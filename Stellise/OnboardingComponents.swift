import SwiftUI

/// 初期設定フローで共通利用する背景。メイン画面の夜空トーンとアクセントを引き継ぐ。
struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#17172F"), Color(hex: "#090912")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Theme.Palette.accent.opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 150, y: -260)

            Circle()
                .fill(Color(hex: "#5AD1E0").opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: -150, y: 320)
        }
        .ignoresSafeArea()
    }
}

struct OnboardingProgressHeader: View {
    let step: Int
    let total: Int

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("初期設定")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(step) / \(total)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.accentLight)
                    .accessibilityLabel("全\(total)ステップ中、\(step)ステップ目")
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Palette.accent, Theme.Palette.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(step) / CGFloat(total))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
}

struct OnboardingHero: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Palette.accentLight)
                .frame(width: 64, height: 64)
                .background(Theme.Palette.accent.opacity(0.16), in: Circle())
                .overlay(Circle().stroke(Theme.Palette.accentLight.opacity(0.22)))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textOnDarkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct OnboardingPrimaryLabel: View {
    let title: String
    var isEnabled = true
    var isLoading = false

    var body: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().tint(.white)
            }
            Text(title)
            if !isLoading {
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
        }
        .font(.headline)
        .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.45))
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
            isEnabled ? Theme.Palette.accent : Color.white.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(color: isEnabled ? Theme.Palette.accent.opacity(0.28) : .clear, radius: 14, y: 7)
    }
}

struct OnboardingCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10))
            )
    }
}

extension View {
    func onboardingCard() -> some View {
        modifier(OnboardingCardModifier())
    }
}
