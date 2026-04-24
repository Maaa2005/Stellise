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
                        // A. 通常画面 (タブ)
                        TabView(selection: $appState.selectedTab) {
                            DayView()
                                .tabItem { Label("朝", systemImage: "sun.max.fill") }
                                .tag(0)
                            
                            NightView()
                                .tabItem { Label("夜", systemImage: "moon.fill") }
                                .tag(1)
                            
                            SettingsView()
                                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                                .tag(2)
                        }
                        .accentColor(.white)
                        .preferredColorScheme(.dark)
                        
                        // B. アラーム画面 (割り込み表示)
                        if appState.isAlarmRinging {
                            AlarmRingingView()
                                .environmentObject(appState)
                                .transition(.opacity.animation(.easeInOut)) // アニメーション付きで出現
                                .zIndex(999) // 確実に最前面へ
                        }
                    }
                    // ★★★ 重要: アラーム状態の変化に合わせて画面を更新する設定 ★★★
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
                    // 夜画面へ: アラーム待機モード
                    Task {
                        // ※ ここで resetNightlyState を呼ぶと、アラーム中にタブが変わった場合に止まってしまうリスクがあるため、
                        // アラームが鳴っていない時だけリセットするようにガードします。
                        if !appState.isAlarmRinging {
                            await appState.resetNightlyState()
                        }
                        await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium)
                        
                        // センサー開始
                        appState.sensorManager.startDetection(threshold: appState.movementThreshold)
                    }
                } else if newTab == 0 {
                    // 朝画面へ
                    Task {
                        appState.sensorManager.stopDetection()
                        await appState.soundAnalyzer.stopAnalyzing()
                        await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium)
                    }
                } else {
                    // 設定画面へ
                    appState.sensorManager.stopDetection()
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
