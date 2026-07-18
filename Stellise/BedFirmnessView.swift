//
//  BedFirmnessView.swift
//  Stellise
//
//  Created by yuu on 2025/11/04.
//


import SwiftUI

// Kivyの <BedFirmnessScreen>: に相当
struct BedFirmnessView: View {
    
    // アプリ全体の「脳」を受け取る
    @EnvironmentObject var appState: AppState
    
    // Kivyの options = [...] に相当
    let options: [(value: Double, text: String)] = [
        (0, "床 / 非常に硬い"),
        (25, "床に布団"),
        (50, "硬めのマットレス"),
        (75, "普通のマットレス"),
        (100, "柔らかいマットレス")
    ]
    
    // -----------------------------------------------------------------
    // UI（見た目）の定義
    // -----------------------------------------------------------------
    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressHeader(step: 2, total: 5)

                ScrollView {
                    VStack(spacing: 24) {
                        OnboardingHero(
                            symbol: "bed.double.fill",
                            title: "寝具の硬さ",
                            description: "睡眠の動きを正しく捉えるため、\n普段使っている寝具に近いものを選んでください。"
                        )
                        .padding(.top, 24)

                        VStack(spacing: 10) {
                            ForEach(options, id: \.value) { option in
                                Button {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        appState.userData.bedFirmness = option.value
                                    }
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: firmnessIcon(for: option.value))
                                            .frame(width: 24)
                                            .foregroundStyle(isSelected(option.value) ? Theme.Palette.accentLight : .white.opacity(0.65))
                                        Text(option.text)
                                            .font(.body.weight(.medium))
                                        Spacer()
                                        Image(systemName: isSelected(option.value) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isSelected(option.value) ? Theme.Palette.accentLight : .white.opacity(0.25))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 52)
                                    .background(
                                        isSelected(option.value) ? Theme.Palette.accent.opacity(0.18) : Color.white.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isSelected(option.value) ? Theme.Palette.accentLight.opacity(0.55) : Color.white.opacity(0.06))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .onboardingCard()

                        NavigationLink {
                            TravelModeSetupView()
                        } label: {
                            OnboardingPrimaryLabel(title: "次へ")
                        }
                        .buttonStyle(PressSpringButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            appState.save()
                            debugLog("ベッドの硬さ設定を保存しました。")
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

    private func isSelected(_ value: Double) -> Bool {
        appState.userData.bedFirmness == value
    }

    private func firmnessIcon(for value: Double) -> String {
        switch value {
        case 0: return "square.fill"
        case 25: return "rectangle.fill"
        case 50: return "bed.double"
        case 75: return "bed.double.fill"
        default: return "cloud.fill"
        }
    }
}

// プレビュー用
struct BedFirmnessView_Previews: PreviewProvider {
    static var previews: some View {
        // プレビューが見やすいように NavigationStack で囲む
        NavigationStack {
            BedFirmnessView()
                .environmentObject(AppState())
        }
    }
}
