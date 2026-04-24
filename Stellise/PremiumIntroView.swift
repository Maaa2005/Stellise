//
//  PremiumIntroView.swift
//  Stellise
//
//  Created by yuu on 2026/03/21.
//

import SwiftUI
import StoreKit

struct PremiumIntroView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    // EULAとプライバシーポリシーのURL
    let eulaURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    // TODO: プライバシーポリシーのURLをご自身のものに書き換えてください
    let privacyURL = URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80e59cb0c9bd2fb0c008")! // 例: 自分のサイトのURLなど
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "crown.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
            
            Text("Stellise Pro")
                .font(.largeTitle).bold()
            
            VStack(alignment: .leading, spacing: 15) {
                FeatureRow(icon: "sparkles", text: "AIによる執事モードのタスク提案")
                FeatureRow(icon: "car.fill", text: "リアルタイム交通状況の自動監視")
                FeatureRow(icon: "moon.zzz.fill", text: "すべての睡眠環境音の解放")
            }
            .padding()

            Spacer()
            
            // プレミアム購入ボタン
            if let product = subscriptionManager.products.first {
                Button(action: {
                    Task {
                        // 1. 購入処理を実行
                        await subscriptionManager.purchase(product)
                        
                        // 2. もし購入が成功してプレミアム状態になっていれば、自動で次の画面へ進む
                        if subscriptionManager.isPremium {
                            await appState.finishOnboarding(didLinkCalendar: appState.userData.calendarLinked)
                        }
                    }
                }) {
                    Text("\(product.displayPrice) / 月で試す")
                        .fontWeight(.bold)
                        .frame(width: 300, height: 50)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                
                // ★追加: サブスクリプションの必須説明文（小さく表示）
                Text("プラン名称: Stellise Pro（月額）\n価格と期間: \(product.displayPrice) / 月\nお支払いはiTunesアカウントに請求されます。期間終了の24時間前までに解約しない限り自動更新されます。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // 無料で始めるボタン
            Button(action: {
                Task { await appState.finishOnboarding(didLinkCalendar: appState.userData.calendarLinked) }
            }) {
                Text("まずは無料で始める")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            // ★追加: 規約へのリンク群
            HStack(spacing: 15) {
                Link("利用規約(EULA)", destination: eulaURL)
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("|").font(.caption).foregroundColor(.secondary)
                
                Link("プライバシーポリシー", destination: privacyURL)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 10)
        }
        .padding()
        .onAppear {
            triggerPermissions()
        }
    }
    
    private func triggerPermissions() {
        // 1. 通知の許可
        appState.requestNotificationPermission()
        
        // 2. 位置情報の許可
        Task {
            try? await appState.locationManager.requestLocation()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.blue).frame(width: 30)
            Text(text).font(.subheadline)
        }
    }
}
