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
    let privacyURL = URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80e59cb0c9bd2fb0c008")!
    
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
            
            // プレミアム購入ボタン（年額を上・強調、月額を下に表示）
            if !subscriptionManager.products.isEmpty {
                VStack(spacing: 10) {
                    ForEach(sortedPlans, id: \.id) { product in
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
                            VStack(spacing: 2) {
                                Text(planTitle(for: product))
                                    .fontWeight(.bold)
                                // App Store Connect で無料トライアルを設定すると自動表示される
                                if let intro = product.subscription?.introductoryOffer,
                                   intro.paymentMode == .freeTrial {
                                    Text("\(periodText(intro.period))無料トライアル付き")
                                        .font(.caption2)
                                }
                            }
                            .frame(width: 300, height: 54)
                            .background(isYearly(product) ? Color.appAccent : Color(.systemGray5))
                            .foregroundStyle(isYearly(product) ? .white : .primary)
                            .cornerRadius(12)
                        }
                    }
                }

                // ★追加: サブスクリプションの必須説明文（小さく表示）
                Text(legalText())
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

            // 機種変更ユーザー向けの復元導線（審査ガイドライン3.1.1でも必須）
            Button(action: {
                Task { await subscriptionManager.restore() }
            }) {
                Text("購入を復元")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            .padding(.top, 2)

            // ★追加: 規約へのリンク群
            HStack(spacing: 15) {
                Link("利用規約(EULA)", destination: eulaURL)
                    .font(.caption)
                    .foregroundColor(.appAccent)

                Text("|").font(.caption).foregroundColor(.secondary)

                Link("プライバシーポリシー", destination: privacyURL)
                    .font(.caption)
                    .foregroundColor(.appAccent)
            }
            .padding(.bottom, 10)
        }
        .padding()
        // ※権限リクエストはここでは出さない。ペイウォールの上に権限ダイアログが被さると
        //   購入率・許可率の両方が下がるため、位置情報はオンボーディング完了時に要求する。
    }

    // MARK: - プラン表示・法定表記（月額/年額・Introductory Offer 対応）

    /// 年額を先頭にして表示（お得なプランを推す）
    private var sortedPlans: [Product] {
        subscriptionManager.products.sorted { isYearly($0) && !isYearly($1) }
    }

    private func isYearly(_ product: Product) -> Bool {
        product.subscription?.subscriptionPeriod.unit == .year
    }

    private func planTitle(for product: Product) -> String {
        if isYearly(product) {
            return "年額 \(product.displayPrice)\(yearlySavingsText)"
        }
        return "月額 \(product.displayPrice)"
    }

    /// 「月額×12」と比べた年額プランの割引率（例: "（22%お得）"）
    private var yearlySavingsText: String {
        guard let monthly = subscriptionManager.products.first(where: { $0.subscription?.subscriptionPeriod.unit == .month }),
              let yearly = subscriptionManager.products.first(where: { isYearly($0) }) else { return "" }
        let fullYear = monthly.price * 12
        guard fullYear > 0 else { return "" }
        let percent = Int(truncating: NSDecimalNumber(decimal: (fullYear - yearly.price) / fullYear * 100))
        return percent > 0 ? "（\(percent)%お得）" : ""
    }

    private func legalText() -> String {
        var lines = ["プラン名称: Stellise Pro"]
        let priceParts = sortedPlans.map { p -> String in
            isYearly(p) ? "年額プラン \(p.displayPrice) / 年" : "月額プラン \(p.displayPrice) / 月"
        }
        if !priceParts.isEmpty {
            lines.append(priceParts.joined(separator: "・"))
        }
        if let trial = sortedPlans.compactMap({ $0.subscription?.introductoryOffer }).first(where: { $0.paymentMode == .freeTrial }) {
            lines.append("無料トライアル終了後、選択したプランの価格で自動更新されます。（トライアル期間: \(periodText(trial.period))）")
        }
        lines.append("お支払いはiTunesアカウントに請求されます。期間終了の24時間前までに解約しない限り自動更新されます。")
        return lines.joined(separator: "\n")
    }

    private func periodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:   return "\(period.value)日間"
        case .week:  return "\(period.value * 7)日間"
        case .month: return "\(period.value)か月間"
        case .year:  return "\(period.value)年間"
        @unknown default: return ""
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.appAccent).frame(width: 30)
            Text(text).font(.subheadline)
        }
    }
}
