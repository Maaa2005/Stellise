import SwiftUI
import FirebaseAuth
import CoreLocation
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @State private var isShowingRedeemSheet = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // --- 1. 移動手段 ---
                Section(header: Text("主な移動手段")) {
                    HStack {
                        TravelModeChip(mode: "transit", text: "電車・バス", icon: "tram.fill")
                        Spacer()
                        TravelModeChip(mode: "driving", text: "車", icon: "car.fill")
                        Spacer()
                        TravelModeChip(mode: "walking", text: "徒歩", icon: "figure.walk")
                    }
                    .padding(.vertical, 5)
                }
                
                // --- 2. アラーム設定 ---
                Section(header: Text("アラーム設定")) {
                    Toggle("スマートアラーム", isOn: $appState.userData.isSmartAlarmEnabled)
                        .tint(.blue)
                    
                    HStack {
                        Text("センサー感度")
                        Spacer()
                        Text(String(format: "%.1f", appState.movementThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.movementThreshold, in: 1.0...3.0, step: 0.1) {
                        Text("センサー感度")
                    }
                }
                
                // --- 3. プレミアムプラン (審査対応) ---
                Section(
                    header: Text("プレミアムプラン"),
                    footer: premiumLegalFooter
                ) {
                    HStack {
                        Text("現在のステータス")
                        Spacer()
                        Text(subscriptionManager.isPremium ? "プレミアム (有効)" : "無料プラン")
                            .foregroundStyle(subscriptionManager.isPremium ? .green : .secondary)
                    }
                    
                    // ★ アップグレードボタン (未加入時のみ表示)
                    if !subscriptionManager.isPremium {
                        ForEach(subscriptionManager.products) { product in
                            Button(action: {
                                Task {
                                    // 実際の購入処理を呼び出す
                                    await subscriptionManager.purchase(product)
                                }
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(product.displayName)
                                            .fontWeight(.bold)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundStyle(.primary) // 文字色が青くなりすぎるのを防ぐ
                        }
                    }
                    
                    // プロモーションコード入力ボタン
                    Button(action: {
                        isShowingRedeemSheet = true
                    }) {
                        HStack {
                            
                            Text("プロモーションコードを入力")
                                .foregroundStyle(.primary)
                        }
                    }
                }
                
                // --- 4. デバッグメニュー ---
                #if DEBUG
                Section(header: Text("🛠 デバッグ (本番では非表示)")) {
                    Toggle("プレミアム強制ON", isOn: $subscriptionManager.isDebugModeEnabled)
                        .tint(.red)
                        .onChange(of: subscriptionManager.isDebugModeEnabled) { _, _ in
                            Task { await subscriptionManager.updateStatus() }
                        }
                }
                #endif
                
                // --- 5. アカウント ---
                Section {
                    Button("ログアウト", role: .destructive) {
                        try? FirebaseAuth.Auth.auth().signOut()
                        appState.needsOnboarding = true
                    }
                }
                
                Section(footer: Text("アカウントを削除すると、これまでの睡眠データや設定がすべて消去され、復元することはできません。")) {
                    Button("アカウントを完全に削除", role: .destructive) {
                        showDeleteAlert = true
                    }
                }
            }
            .navigationTitle("設定")
            .offerCodeRedemption(isPresented: $isShowingRedeemSheet) // プロモコード入力シート
            .alert("本当に削除しますか？", isPresented: $showDeleteAlert) {
                Button("キャンセル", role: .cancel) { }
                Button("削除する", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("この操作は取り消せません。\n※サブスクリプションをご利用中の場合は、別途App Storeの設定から解約が必要です。")
            }
        }
    }
    
    // ==========================================
    // MARK: - ヘルパー関数とコンポーネント
    // ==========================================
    
    private var premiumLegalFooter: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("プラン名称: Stellise Pro（月額）")
                Text("価格と期間: ¥500 / 月")
                // ★追加: 自動更新の注意書き
                Text("お支払いはiTunesアカウントに請求されます。期間終了の24時間前までに解約しない限り自動更新されます。")
                
                VStack(alignment: .leading, spacing: 4) {
                    Link("利用規約(EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        .foregroundStyle(.blue)
                    
                    // ★追加: プライバシーポリシーのリンク（※URLを書き換えてください）
                    Link("プライバシーポリシー", destination: URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80e59cb0c9bd2fb0c008")!)
                        .foregroundStyle(.blue)
                    
                    Link("サブスクリプションの管理・解約", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        .foregroundStyle(.blue)
                }
                .font(.footnote)
                
                Text("※上記規約に同意の上ご利用ください。")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }

    private func deleteAccount() {
        guard let user = FirebaseAuth.Auth.auth().currentUser else { return }
        
        user.delete { error in
            if let error = error {
                print("❌ アカウント削除エラー: \(error.localizedDescription)")
            } else {
                appState.needsOnboarding = true
            }
        }
    }
}

// 別構造体として定義
struct TravelModeChip: View {
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
            appState.save()
            appState.needsScheduleRecalculation = true
        }) {
            VStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(text)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .frame(width: 80, height: 60)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemGray6))
            .foregroundStyle(isSelected ? .blue : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
