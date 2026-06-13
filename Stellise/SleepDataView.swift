//
//  SleepDataView.swift
//  Stellise
//
//  ホームから左スワイプで現れる睡眠データ画面。睡眠スコア/サマリー/アドバイスを表示し、
//  設定への導線もここに集約する（タブバー廃止に伴い、設定は歯車ではなくこの画面の中へ）。
//

import SwiftUI

struct SleepDataView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var isShowingSettings = false
    @State private var isShowingFullReport = false

    private var hasReport: Bool { appState.lastSleepScore > 0 }

    var body: some View {
        ZStack {
            LinearGradient.nightImmersive.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("睡眠データ")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textOnDark)
                        .padding(.top, 28)

                    if hasReport {
                        scoreCard
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
                    } else {
                        emptyCard
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

    // MARK: - 部品

    private var scoreCard: some View {
        VStack(spacing: 6) {
            Text("昨晩のスコア")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textOnDarkMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(appState.lastSleepScore)")
                    .font(.system(size: 76, weight: .thin, design: .rounded))
                    .foregroundStyle(Theme.Palette.textOnDark)
                Text("点")
                    .font(.title3)
                    .foregroundStyle(Theme.Palette.textOnDarkMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .glassCard()
    }

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
