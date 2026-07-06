import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import StoreKit
import AlarmKit
import AVFoundation
import EventKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    @State private var isShowingRedeemSheet = false
    @State private var showDeleteAlert = false
    @State private var alarmAuthState: AlarmManager.AuthorizationState = .notDetermined
    @State private var micPermission: AVAudioSession.RecordPermission = .undetermined
    @State private var calendarStatus: EKAuthorizationStatus = .notDetermined
    
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
                        .tint(.appAccent)

                    HStack {
                        Text("センサー感度")
                        Spacer()
                        Text(String(format: "%.1f", appState.movementThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $appState.movementThreshold, in: 1.0...3.0, step: 0.1) {
                        Text("センサー感度")
                    }

                    // AlarmKit 権限ステータス
                    HStack(spacing: 12) {
                        Image(systemName: alarmAuthIcon)
                            .foregroundStyle(alarmAuthColor)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("アラーム権限")
                            Text(alarmAuthStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        switch alarmAuthState {
                        case .authorized:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .notDetermined:
                            Button("許可する") {
                                Task {
                                    await appState.requestNotificationPermission()
                                    alarmAuthState = AlarmManager.shared.authorizationState
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.appAccent)
                        case .denied:
                            Button("設定で変更") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        @unknown default:
                            EmptyView()
                        }
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

                    // 機種変更・再インストール時の復元導線（審査ガイドライン3.1.1でも必須）
                    Button(action: {
                        Task { await subscriptionManager.restore() }
                    }) {
                        Text("購入を復元")
                            .foregroundStyle(.primary)
                    }
                }
                
                // --- 4. アプリの権限 ---
                Section(header: Text("アプリの権限")) {
                    permissionRow(
                        icon: "location.fill",
                        title: "位置情報",
                        statusText: locationStatusText,
                        color: locationStatusColor,
                        state: locationPermState
                    ) {
                        appState.locationManager.requestAuthorization()
                    }

                    permissionRow(
                        icon: "mic.fill",
                        title: "マイク",
                        statusText: micStatusText,
                        color: micStatusColor,
                        state: micPermState
                    ) {
                        AVAudioSession.sharedInstance().requestRecordPermission { granted in
                            DispatchQueue.main.async {
                                micPermission = AVAudioSession.sharedInstance().recordPermission
                            }
                        }
                    }

                    permissionRow(
                        icon: "calendar",
                        title: "カレンダー",
                        statusText: calendarStatusText,
                        color: calendarStatusColor,
                        state: calendarPermState
                    ) {
                        Task {
                            _ = await appState.calendarManager.requestAccess()
                            calendarStatus = EKEventStore.authorizationStatus(for: .event)
                        }
                    }
                }

                // --- 5. デバッグメニュー ---
                #if DEBUG
                Section(header: Text("🛠 デバッグ (本番では非表示)")) {
                    Toggle("プレミアム強制ON", isOn: $subscriptionManager.isDebugModeEnabled)
                        .tint(.red)
                        .onChange(of: subscriptionManager.isDebugModeEnabled) { _, _ in
                            Task { await subscriptionManager.updateStatus() }
                        }

                    Button {
                        appState.selectedTab = appState.selectedTab == 1 ? 0 : 1
                    } label: {
                        HStack {
                            Image(systemName: appState.selectedTab == 1 ? "sun.max.fill" : "moon.fill")
                            Text(appState.selectedTab == 1 ? "朝画面に切替" : "夜画面に切替")
                        }
                    }
                    .foregroundStyle(.red)
                }
                #endif
                
                // --- 6. クレジット ---
                // OtoLogic音素材は CC BY 4.0（商用可・クレジット表記必須）。
                // この表記がライセンス上の必須条件なので削除しないこと。
                Section(
                    header: Text("クレジット"),
                    footer: Text("アラーム音・環境音には OtoLogic の音素材を使用しています。")
                ) {
                    Link(destination: URL(string: "https://otologic.jp")!) {
                        HStack {
                            Text("サウンド素材: OtoLogic")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://creativecommons.org/licenses/by/4.0/deed.ja")!) {
                        HStack {
                            Text("ライセンス: CC BY 4.0")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // --- 7. アカウント ---
                // ※「ログアウト」は撤去: 本アプリは匿名アカウントのみでサインイン機能が無いため、
                //   ログアウトは意味を持たず（データが孤立するだけ）誤解を招く。
                Section(footer: Text("アカウントを削除すると、これまでの睡眠データや設定がすべて消去され、復元することはできません。")) {
                    Button("アカウントを完全に削除", role: .destructive) {
                        showDeleteAlert = true
                    }
                }
            }
            .navigationTitle("設定")
            .offerCodeRedemption(isPresented: $isShowingRedeemSheet)
            .onAppear {
                alarmAuthState = AlarmManager.shared.authorizationState
                micPermission = AVAudioSession.sharedInstance().recordPermission
                calendarStatus = EKEventStore.authorizationStatus(for: .event)
            } // プロモコード入力シート
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

    // MARK: - 共通権限 Row ビルダー

    enum PermState { case granted, notDetermined, denied }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        statusText: String,
        color: Color,
        state: PermState,
        onRequest: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notDetermined:
                Button("許可する", action: onRequest)
                    .buttonStyle(.bordered)
                    .tint(.appAccent)
            case .denied:
                Button("設定で変更") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    // MARK: - 位置情報

    private var locationPermState: PermState {
        switch appState.locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .granted
        case .denied, .restricted:                    return .denied
        default:                                       return .notDetermined
        }
    }

    private var locationStatusText: String {
        switch appState.locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return "位置情報が許可されています"
        case .denied:                                  return "拒否されました。設定アプリから変更できます"
        case .restricted:                              return "制限されています"
        default:                                       return "まだ許可されていません"
        }
    }

    private var locationStatusColor: Color {
        switch appState.locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .green
        case .denied, .restricted:                    return .orange
        default:                                       return .secondary
        }
    }

    // MARK: - マイク

    private var micPermState: PermState {
        switch micPermission {
        case .granted:      return .granted
        case .denied:       return .denied
        default:            return .notDetermined
        }
    }

    private var micStatusText: String {
        switch micPermission {
        case .granted:  return "マイクが許可されています"
        case .denied:   return "拒否されました。設定アプリから変更できます"
        default:        return "まだ許可されていません"
        }
    }

    private var micStatusColor: Color {
        switch micPermission {
        case .granted:  return .green
        case .denied:   return .orange
        default:        return .secondary
        }
    }

    // MARK: - カレンダー

    private var calendarPermState: PermState {
        switch calendarStatus {
        case .fullAccess:    return .granted
        case .notDetermined: return .notDetermined
        default:             return .denied
        }
    }

    private var calendarStatusText: String {
        switch calendarStatus {
        case .fullAccess:    return "カレンダーが許可されています"
        case .denied:        return "拒否されました。設定アプリから変更できます"
        case .restricted:    return "制限されています"
        case .writeOnly:     return "書き込み専用（読み取り不可）"
        default:             return "まだ許可されていません"
        }
    }

    private var calendarStatusColor: Color {
        switch calendarStatus {
        case .fullAccess:    return .green
        case .denied, .restricted, .writeOnly: return .orange
        default:             return .secondary
        }
    }

    // MARK: - AlarmKit

    private var alarmAuthIcon: String {
        switch alarmAuthState {
        case .authorized:    return "bell.fill"
        case .denied:        return "bell.slash.fill"
        default:             return "bell.badge.fill"
        }
    }

    private var alarmAuthColor: Color {
        switch alarmAuthState {
        case .authorized: return .green
        case .denied:     return .orange
        default:          return .secondary
        }
    }

    private var alarmAuthStatusText: String {
        switch alarmAuthState {
        case .authorized:    return "アラームが許可されています"
        case .denied:        return "拒否されました。設定アプリから変更できます"
        default:             return "まだ許可されていません"
        }
    }

    // ストアフロントの実価格を表示（ハードコードだと海外ストアや価格改定でズレるため）
    private var displayPriceText: String {
        if let product = subscriptionManager.products.first {
            return "\(product.displayPrice) / 月"
        }
        return "App Store 表示価格 / 月"
    }

    private var premiumLegalFooter: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("プラン名称: Stellise Pro（月額）")
                Text("価格と期間: \(displayPriceText)")
                // ★追加: 自動更新の注意書き
                Text("お支払いはiTunesアカウントに請求されます。期間終了の24時間前までに解約しない限り自動更新されます。")
                
                VStack(alignment: .leading, spacing: 4) {
                    Link("利用規約(EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        .foregroundStyle(.appAccent)
                    
                    // ★追加: プライバシーポリシーのリンク（※URLを書き換えてください）
                    Link("プライバシーポリシー", destination: URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80e59cb0c9bd2fb0c008")!)
                        .foregroundStyle(.appAccent)
                    
                    Link("サブスクリプションの管理・解約", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        .foregroundStyle(.appAccent)
                }
                .font(.footnote)
                
                Text("※上記規約に同意の上ご利用ください。")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }

    private func deleteAccount() {
        Task {
            // 1. サーバ側データ（Firestore）を削除
            if let user = Auth.auth().currentUser {
                try? await Firestore.firestore().collection("users").document(user.uid).delete()
                // 2. 認証アカウント（匿名）を削除
                do {
                    try await user.delete()
                } catch {
                    print("❌ アカウント削除エラー: \(error.localizedDescription)")
                }
            }
            // 3. 端末内データを削除してオンボーディングへ戻す
            await MainActor.run {
                appState.resetAllUserData()
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
            .background(isSelected ? Color.appAccent.opacity(0.2) : Color(.systemGray6))
            .foregroundStyle(isSelected ? .appAccent : .primary)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.appAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
