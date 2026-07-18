//
//  TravelModeSetupView.swift
//  Stellise
//
//  Created by yuu on 2025/11/11.
//


import SwiftUI

// Kivyの <SettingsScreen> の「移動手段」部分を移植
struct TravelModeSetupView: View {
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressHeader(step: 3, total: 5)

                ScrollView {
                    VStack(spacing: 24) {
                        OnboardingHero(
                            symbol: "location.fill",
                            title: "主な移動手段",
                            description: "予定に間に合う起床時刻を計算するため、\n普段もっともよく使う移動手段を選んでください。"
                        )
                        .padding(.top, 32)

                        VStack(spacing: 12) {
                            OnboardingTravelModeChip(mode: "transit", text: "公共交通機関", detail: "電車・バスなど", icon: "tram.fill")
                            OnboardingTravelModeChip(mode: "driving", text: "車", detail: "渋滞を考慮", icon: "car.fill")
                            OnboardingTravelModeChip(mode: "walking", text: "徒歩", detail: "徒歩時間を計算", icon: "figure.walk")
                        }
                        .onboardingCard()

                        NavigationLink {
                            TaskSetupView()
                        } label: {
                            OnboardingPrimaryLabel(title: "次へ")
                        }
                        .buttonStyle(PressSpringButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            appState.save()
                            debugLog("移動手段 (\(appState.userData.travelMode)) を保存しました。")
                        })
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// --- 移動手段チップのUI（部品） ---
// SettingsView.swift から流用 (アイコンを追加)
private struct OnboardingTravelModeChip: View {
    @EnvironmentObject var appState: AppState
    let mode: String
    let text: String
    let detail: String
    let icon: String
    
    private var isSelected: Bool {
        appState.userData.travelMode == mode
    }
    
    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                appState.userData.travelMode = mode
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Theme.Palette.accent.opacity(0.28) : Color.white.opacity(0.07), in: Circle())
                    .foregroundStyle(isSelected ? Theme.Palette.accentLight : .white.opacity(0.72))

                VStack(alignment: .leading, spacing: 3) {
                    Text(text).font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textOnDarkMuted)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.Palette.accentLight : .white.opacity(0.25))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 70)
            .background(isSelected ? Theme.Palette.accent.opacity(0.16) : Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Theme.Palette.accentLight.opacity(0.5) : Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

// プレビュー用
struct TravelModeSetupView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TravelModeSetupView()
                .environmentObject(AppState())
        }
    }
}
