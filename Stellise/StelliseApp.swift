import SwiftUI
import Combine
import FirebaseCore
import FirebaseAuth
import AlarmKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // 匿名サインイン: サーバAPIのBearer認証・Firestoreのプレミアム状態フォールバック・
        // アカウント削除を機能させるために必須（サインインUIは持たない）
        if Auth.auth().currentUser == nil {
            Auth.auth().signInAnonymously { result, error in
                if let error = error {
                    print("❌ 匿名サインイン失敗: \(error.localizedDescription)")
                } else if let uid = result?.user.uid {
                    print("✅ 匿名サインイン成功: \(uid)")
                }
            }
        }
        return true
    }
}

@main
struct StelliseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject private var appState = AppState()
    @StateObject private var subscriptionManager = SubscriptionManager()
    
    @State private var isLoading: Bool = true
    @State private var homePage: Int = 1   // 0=睡眠データ（右スワイプで表示）, 1=ホーム
    // 背景コンディション用の現在時。アプリを開きっぱなしでも時間帯の境界(夕暮れ・夜など)で
    // 背景が切り替わるよう、毎分チェックして「時」が変わった時だけ更新する。
    @State private var currentHour: Int = Calendar.current.component(.hour, from: Date())
    private let hourTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // --- 1. ローディング ---
                if isLoading {
                    LoadingView()
                        .onAppear {
                            checkTimeAndSwitchTab()
                            Background3DView.preheat()  // 月テクスチャ等を先に生成（初回表示の空白防止）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation { isLoading = false }
                            }
                        }
                        .zIndex(200) // 最優先
                }
                // --- 2. 初期設定 (オンボーディング) ---
                else if appState.needsOnboarding {
                    WelcomeView()
                        .environmentObject(appState)
                        .zIndex(150)
                }
                // --- 3. メインアプリ ---
                else {
                    ZStack {
                        // A. 横ページング: 睡眠データ(0) ⇄ ホーム(1)。ホームから右スワイプで睡眠データへ。
                        TabView(selection: $homePage) {
                            SleepDataView()
                                .tag(0)

                            // 時間駆動ホーム。背景は1枚を共有（朝⇄夜で再生成されず連続）。
                            ZStack {
                                Background3DView(condition: homeCondition, nightBoost: isTrueNightWeather)
                                    .ignoresSafeArea()
                                Group {
                                    if appState.selectedTab == 1 {
                                        NightView()
                                    } else {
                                        DayView()
                                    }
                                }
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 1.2), value: appState.selectedTab)
                            }
                            .tag(1)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .ignoresSafeArea()

                        // B. アラーム画面 (割り込み表示)
                        if appState.isAlarmRinging {
                            AlarmRingingView()
                                .environmentObject(appState)
                                .transition(.opacity.animation(.easeInOut))
                                .zIndex(999)
                        }
                    }
                    .preferredColorScheme(.dark)
                    .animation(.easeInOut, value: appState.isAlarmRinging)
                }
                if appState.selectedTab == 1 && appState.isFaceDown {
                                    Color.black
                                        .ignoresSafeArea() // セーフエリア(ノッチやホームバー)も完全に無視して覆う
                                        .zIndex(9999)      // 確実に全UIの上に被せる
                                }
                            
            }
            .statusBarHidden(true)
            .environmentObject(appState)
            .environmentObject(subscriptionManager)
            
            // --- ライフサイクル管理 ---
            .onChange(of: appState.selectedTab) { oldTab, newTab in
                if newTab == 1 {
                    // 夜へ: アラーム待機モード。タスク自動生成はしない（アラーム発火 or 手動生成）。
                    Task {
                        // アラーム中にモードが変わっても止まらないようガード
                        if !appState.isAlarmRinging {
                            await appState.resetNightlyState()
                        }
                        // センサー開始
                        appState.sensorManager.startDetection(threshold: appState.movementThreshold)
                    }
                } else {
                    // 朝へ: センサー・音声解析を停止（タスクは自動生成しない）
                    Task {
                        appState.sensorManager.stopDetection()
                        await appState.soundAnalyzer.stopAnalyzing()
                    }
                }
            }
            .onReceive(hourTick) { date in
                let hour = Calendar.current.component(.hour, from: date)
                guard hour != currentHour else { return }
                currentHour = hour   // 背景コンディション(homeCondition)を再評価させる
                checkTimeAndSwitchTab()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    currentHour = Calendar.current.component(.hour, from: Date())
                    checkTimeAndSwitchTab()
                    handlePendingAlarmKitAlarm()
                    Task {
                        await appState.fetchWeatherForCurrentLocation()
                        await subscriptionManager.updateStatus()
                    }
                }
            }
        }
    }
    
    /// 共有背景のコンディション。時刻＋天気から導出し、朝晩の切替に薄明(dawn/dusk)を挟む。
    private var homeCondition: WeatherCondition {
        let hour = currentHour
        let weather = WeatherCondition.from(backgroundImageName: appState.backgroundImageName)
        switch hour {
        case 5..<7:   return .dawn                                  // 夜明け前
        case 7..<17:  return weather == .night ? .clear : weather   // 日中は天気連動
        case 17..<19: return .dusk                                  // 夕暮れ
        default:
            // 深夜も「晴れ」に固定せず、雨/曇り/雪ならそのまま反映する（nightBoostで暗さを補う）
            switch weather {
            case .rain, .cloudy, .snow: return weather
            default: return .night
            }
        }
    }

    /// 深夜帯なのに天気コンディション(雨/曇り/雪)を出している場合 true。
    /// Background3DView 側でさらに暗く落とすトリガーに使う。
    private var isTrueNightWeather: Bool {
        guard !(5..<19).contains(currentHour) else { return false }
        switch homeCondition {
        case .rain, .cloudy, .snow: return true
        default: return false
        }
    }

    // AlarmKit がアプリをアクティブ化したとき、alerting 状態のアラームがあれば発火させる
    @MainActor
    private func handlePendingAlarmKitAlarm() {
        guard !appState.isAlarmRinging else { return }
        do {
            let alarms = try AlarmManager.shared.alarms
            // 朝アラーム または スヌーズガードアラームが鳴動中なら画面を立ち上げる
            let triggerIDs: Set<UUID> = [appState.morningAlarmID, appState.snoozeGuardAlarmID]
            if alarms.first(where: { triggerIDs.contains($0.id) && $0.state == .alerting }) != nil {
                appState.isAlarmFinished = false
                appState.isAlarmRinging = true
                appState.startAlarmEffects()
            }
        } catch {
            print("⚠️ AlarmKit: アラーム状態の確認に失敗: \(error.localizedDescription)")
        }
    }

    // 時間帯による自動タブ切り替え
    private func checkTimeAndSwitchTab() {
        // アラーム中やオンボーディング中は勝手に切り替えない
        if appState.isAlarmRinging || appState.needsOnboarding { return }

        let hour = Calendar.current.component(.hour, from: Date())

        // 朝 4:00 〜 夕方 18:00 は「朝画面」
        if hour >= 4 && hour < 18 {
            if appState.selectedTab != 0 {
                appState.selectedTab = 0
            }
        } else {
            if appState.selectedTab != 1 {
                appState.selectedTab = 1
            }
        }
    }
}

