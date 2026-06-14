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

    private var scoreRingCard: some View {
        let score = appState.lastSleepScore
        return HStack(spacing: 22) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(CGFloat(score) / 100, 1))
                    .stroke(
                        AngularGradient(colors: [scoreColor(score).opacity(0.7), scoreColor(score)],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Palette.textOnDark)
                    Text("点")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textOnDarkMuted)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 6) {
                Text("昨晩の睡眠")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textOnDarkMuted)
                Text(scoreLabel(score))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(scoreColor(score))
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .glassCard()
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
