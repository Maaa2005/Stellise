//
//  SleepDataView.swift
//  Stellise
//
//  ホームから右スワイプで現れる睡眠データ画面。睡眠スコア(リングゲージ)・各設定の要約・
//  AIサマリー/アドバイスを表示し、設定への導線(右上の小さな歯車)もここに集約する。
//

import SwiftUI

struct SleepDataView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var isShowingSettings = false
    @State private var isShowingFullReport = false
    /// ヒーロー・スコア円のアニメ用。onAppearで0→スコアまでリングとカウントを伸ばす。
    @State private var ringProgress: CGFloat = 0
    @State private var countUp: Double = 0

    private var hasReport: Bool { appState.lastSleepScore > 0 }
    private var alarmText: String {
        String(format: "%02d:%02d", appState.userData.alarmHour, appState.userData.alarmMinute)
    }

    var body: some View {
        ZStack {
            LinearGradient.nightImmersive.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("睡眠データ")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textOnDark)
                        .padding(.top, 28)

                    if hasReport {
                        scoreRingCard
                    } else {
                        emptyCard
                    }

                    // 今夜の設定サマリー（チップ）
                    infoChips

                    if hasReport {
                        if let summary = appState.lastSleepSummary, !summary.isEmpty {
                            infoCard(title: "AIサマリー", icon: "sparkles", body: summary)
                        }
                        if let advice = appState.lastSleepAdvice, !advice.isEmpty {
                            infoCard(title: "アドバイス", icon: "lightbulb.fill", body: advice)
                        }
                        Button { isShowingFullReport = true } label: {
                            Text("詳細レポートを見る")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.Palette.accentLight)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }

            // 設定は右上に小さく
            settingsGear
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(subscriptionManager)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingFullReport) {
            SleepReportModalView()
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - スコア（リングゲージ）

    /// パープル〜ブルーのヒーロー・スコア円。大きく中央に置き、カウントアップで魅せる。
    private var scoreRingCard: some View {
        let score = appState.lastSleepScore
        let ringSize: CGFloat = 220
        // パープル→ブルーのアングラーグラデ（先頭=末尾でつなぎ目を消す）
        let ringGradient = AngularGradient(
            gradient: Gradient(colors: [
                Color(hex: "#6C5CE0"), Color(hex: "#8B7CF6"),
                Color(hex: "#6CA8FF"), Color(hex: "#5AD1E0"),
                Color(hex: "#6C5CE0")
            ]),
            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))

        return VStack(spacing: 18) {
            Text("昨晩の睡眠")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textOnDarkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                // トラック
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 16)
                // 進捗（パープル〜ブルー）＋発光
                Circle()
                    .trim(from: 0, to: ringProgress)
                    .stroke(ringGradient, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(hex: "#8B7CF6").opacity(0.5), radius: 12)

                // 中央: カウントアップする大きなスコア ＋ / 100 ＋ ラベル
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        CountUpNumber(value: countUp)
                        Text("/100")
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Palette.textOnDarkMuted)
                    }
                    Text(scoreLabel(score))
                        .font(.headline)
                        .foregroundStyle(scoreColor(score))
                }
            }
            .frame(width: ringSize, height: ringSize)
            .frame(maxWidth: .infinity)
        }
        .padding(26)
        .glassCard()
        .onAppear {
            // 0 → スコアへ、リングとカウントを同時にイージング
            ringProgress = 0; countUp = 0
            withAnimation(.easeOut(duration: 1.1)) {
                ringProgress = min(CGFloat(score) / 100, 1)
                countUp = Double(score)
            }
        }
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 85...:   return Theme.Palette.accentLight
        case 70..<85: return Color(hex: "#5BD6A8")
        case 50..<70: return Color(hex: "#F0B86A")
        default:      return Theme.Palette.warning
        }
    }
    private func scoreLabel(_ s: Int) -> String {
        switch s {
        case 85...:   return "ぐっすり"
        case 70..<85: return "良好"
        case 50..<70: return "ふつう"
        default:      return "浅め"
        }
    }

    // MARK: - 設定サマリーのチップ

    private var infoChips: some View {
        HStack(spacing: 12) {
            chip(icon: "bell.fill", label: "アラーム", value: alarmText)
            chip(icon: "wand.and.stars", label: "スマート",
                 value: appState.userData.isSmartAlarmEnabled ? "ON" : "OFF")
            chip(icon: "moon.zzz.fill", label: "環境音",
                 value: appState.sleepSoundManager.selectedSound.rawValue)
        }
    }

    private func chip(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.accentLight)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.Palette.textOnDark)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.textOnDarkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassCard(cornerRadius: Theme.Radius.small)
    }

    // MARK: - サマリー/アドバイス・空状態

    private func infoCard(title: String, icon: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.accentLight)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.textOnDark)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textOnDarkMuted)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .glassCard()
    }

    private var emptyCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(Theme.Palette.accentLight)
            Text("まだ睡眠データがありません")
                .font(.headline)
                .foregroundStyle(Theme.Palette.textOnDark)
            Text("夜にアラームをセットして眠ると、\n翌朝ここにAIの睡眠レポートが出ます。")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Palette.textOnDarkMuted)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .glassCard()
    }

    /// カウントアップする大きなスコア数字。Animatable準拠で毎フレーム描き直す。
    private struct CountUpNumber: View, Animatable {
        var value: Double
        var animatableData: Double {
            get { value }
            set { value = newValue }
        }
        var body: some View {
            Text("\(Int(value.rounded()))")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.textOnDark)
                .monospacedDigit()
        }
    }

    /// 右上に小さく置く設定ボタン。
    private var settingsGear: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.trailing, 22)
            }
            Spacer()
        }
        .padding(.top, 30)
    }
}
