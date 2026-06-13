import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
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
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // --- 1. ローディング ---
                if isLoading {
                    LoadingView()
                        .onAppear {
                            checkTimeAndSwitchTab()
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

                            // 時間駆動ホーム（朝⇄夜を薄明でクロスフェード）
                            Group {
                                if appState.selectedTab == 1 {
                                    NightView()
                                } else {
                                    DayView()
                                }
                            }
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 1.2), value: appState.selectedTab)
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    checkTimeAndSwitchTab()
                    Task {
                        await appState.fetchWeatherForCurrentLocation()
                        await subscriptionManager.updateStatus()
                    }
                }
            }
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

