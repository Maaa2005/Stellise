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
        VStack {
            Text("ステップ 4 / 5")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)

            VStack(spacing: 20) {
                Spacer()

                Text("主な移動手段は\n何ですか？")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("カレンダーの予定から、交通時間を考慮した出発時刻を計算するために使用します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // --- Kivyの self.travel_mode_chips (VStackに変更) ---
                VStack(spacing: 15) {
                    OnboardingTravelModeChip(mode: "transit", text: "公共交通機関", icon: "tram.fill")
                    OnboardingTravelModeChip(mode: "driving", text: "車", icon: "car.fill")
                    OnboardingTravelModeChip(mode: "walking", text: "徒歩", icon: "figure.walk")
                }
                .padding(.vertical, 30)

                // "次へ" ボタン (TaskSetupViewへ)
                NavigationLink {
                    TaskSetupView()
                } label: {
                    Text("次へ")
                        .fontWeight(.semibold)
                        .frame(width: 300, height: 50)
                        .background(Color.blue)
                        .foregroundStyle(Color.white)
                        .cornerRadius(10)
                }
                .padding(.top, 20)
                .simultaneousGesture(TapGesture().onEnded {
                    // ★ 選択した移動手段を保存
                    appState.save()
                    print("移動手段 (\(appState.userData.travelMode)) を保存しました。")
                })
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("移動手段")
    }
}

// --- 移動手段チップのUI（部品） ---
// SettingsView.swift から流用 (アイコンを追加)
private struct OnboardingTravelModeChip: View {
    @EnvironmentObject var appState: AppState
    let mode: String
    let text: String
    let icon: String
    
    private var isSelected: Bool {
        appState.userData.travelMode == mode
    }
    
    var body: some View {
        Button(action: {
            appState.userData.travelMode = mode
            // (保存は「次へ」ボタンが押された時に行う)
        }) {
            HStack {
                Image(systemName: icon)
                Text(text)
            }
            .font(.headline)
            .fontWeight(isSelected ? .bold : .regular)
            .frame(maxWidth: 250, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(isSelected ? .blue : Color(.systemGray5))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(15)
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
