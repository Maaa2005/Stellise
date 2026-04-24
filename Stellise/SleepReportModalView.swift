//
//  SleepReportModalView.swift
//  Stellise
//
//  Created by yuu on 2025/11/07.
//


import SwiftUI

struct SleepReportModalView: View {
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss // モーダルを閉じるための仕組み

    var body: some View {
        VStack(spacing: 24) {
            
            // 1. ヘッダー (タイトルと閉じるボタン)
            HStack {
                Text("昨晩のAI睡眠レポート")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.gray.opacity(0.4))
                }
            }
            
            // 2. 睡眠スコア (backend.py が計算したスコア)
            Text("\(appState.lastSleepScore) 点")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(scoreColor())
            
            // 3. AIサマリー
            VStack(alignment: .leading, spacing: 8) {
                Text("🤖 AIのサマリー")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(appState.lastSleepSummary ?? "レポートを生成中...")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial) // すりガラス風
                    .cornerRadius(12)
            }
            
            // 4. AIアドバイス
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 AIのアドバイス")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text(appState.lastSleepAdvice ?? "...")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .cornerRadius(12)
            }
            
            Spacer() // 残りのスペースを埋める
            Text("※ 注意: このレポートはAIが生成したものであり、医学的な診断や治療の代わりになるものではありません。健康に関する問題については、必ず専門医にご相談ください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 10)

                    
        }
        .padding(30) // モーダル内の余白
    }
    
    /// スコアに応じて文字色を変えるヘルパー関数
    private func scoreColor() -> Color {
        switch appState.lastSleepScore {
        case 90...100:
            return .blue
        case 70..<90:
            return .green
        case 50..<70:
            return .orange
        default:
            return .red
        }
    }
}

// プレビュー用
struct SleepReportModalView_Previews: PreviewProvider {
    static var previews: some View {
        let previewState = AppState()
        previewState.lastSleepScore = 85
        previewState.lastSleepSummary = "全体的に静かな睡眠でしたが、中盤にいびきが数回検知されました。"
        previewState.lastSleepAdvice = "枕の高さを調整してみるか、寝る前にリラックスできる音楽を聴くことをお勧めします。"
        
        return SleepReportModalView()
            .environmentObject(previewState)
    }
}
