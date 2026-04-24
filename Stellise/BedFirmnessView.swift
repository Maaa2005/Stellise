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
        VStack {
            Text("ステップ 3 / 5")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)

            VStack(spacing: 20) {
                Spacer()

                Text("寝具の硬さは\nどのくらいですか？")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)

                Text("マットレスの硬さは、睡眠追跡の精度と快適さの推奨に影響します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // --- Kivyの <MDList> に相当 ---
                // $appState.userData.bedFirmness を直接変更するリスト
                List {
                    ForEach(options, id: \.value) { option in
                        Button(action: {
                            // 項目がタップされたら、脳(appState)の値を直接更新
                            appState.userData.bedFirmness = option.value
                        }) {
                            HStack {
                                Text(option.text)
                                Spacer()
                                // 選択中の項目にチェックマークを付ける
                                if appState.userData.bedFirmness == option.value {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary) // ボタンの文字色をデフォルトに戻す
                    }
                }
                .frame(height: 300) // リストの高さを固定
                .listStyle(.insetGrouped) // リストのスタイル
                
                // --- Kivyの <MDSlider> に相当 ---
                // $appState.userData.bedFirmness を直接変更するスライダー
                Slider(
                    value: $appState.userData.bedFirmness, // 脳(appState)の値を直接連動
                    in: 0...100, // 最小値・最大値
                    step: 25 // 25刻み
                )
                .padding(.horizontal)

                // Kivyの MDRaisedButton("次へ")
                // ★★★ "Button" を "NavigationLink" に変更 ★★★
                NavigationLink {
                                    // 遷移先のView
                                TravelModeSetupView()
                                } label: {
                                    // ボタンの見た目（中身は変更なし）
                                    Text("次へ")
                                        .fontWeight(.semibold)
                                        .frame(width: 300, height: 50)
                                        .background(Color.blue)
                                        .foregroundStyle(Color.white)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 20)
                                // ★★★ "NavigationLink" が押された瞬間に保存処理を実行 ★★★
                                .simultaneousGesture(TapGesture().onEnded {
                                    appState.save()
                                    print("ベッドの硬さ設定を保存しました。")
                                })
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("寝具の硬さ")
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
