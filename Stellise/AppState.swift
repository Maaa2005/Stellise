import SwiftUI
import Foundation
import Combine
import EventKit
import AVFoundation
import AudioToolbox
import CoreLocation
import FirebaseAuth
import MapKit
import UserNotifications
import AlarmKit
import WidgetKit


struct TaskFeedback: Codable, Hashable {
    let taskTitle: String
    let isGood: Bool
    let date: Date
}


// ==========================================
// MARK: - API通信用データ構造体
// ==========================================

struct TaskSuggestionRequest: Encodable {
    let user_name: String
    let weather_info: WeatherInfoForAI?
    let sleep_score: Int
    let calendar_events: [CalendarEventForAI]
    let user_master_tasks: [MasterTaskForAI]
    let departure_time: String
    let is_premium: Bool
    let feedback_history: [TaskFeedbackForAI]?
}
struct TaskFeedbackForAI: Encodable {
    let title: String
    let is_good: Bool
}
struct WeatherInfoForAI: Encodable {
    struct Main: Encodable { let temp: Double }
    struct Weather: Encodable { let description: String }
    let main: Main
    let weather: [Weather]
}

struct CalendarEventForAI: Encodable {
    let title: String
    let start: String
    let end: String
}

struct MasterTaskForAI: Encodable {
    let title: String
}

// 天気レスポンス定義


// AlarmKit でのアラームに付加するカスタムメタデータ（不要だが型引数として必要）
struct StelliSeAlarmMetadata: AlarmMetadata {}

// ==========================================
// MARK: - AppState (アプリの脳・統合版)
// ==========================================

@MainActor
class AppState: ObservableObject {
    
    private var snoozeGuardTask: Task<Void, Never>?
    @Published var isAlarmFinished: Bool = false // ★追加: アラーム完了フラグ
    // 設定
    @Published var sleepSoundManager = SleepSoundManager()
    private let serverBaseURL = "https://aisleep.pythonanywhere.com"
    private let appGroupID = "group.com.stellise"
    
    // MARK: - データモデル
    @Published var userData: UserData
    /// 今日のタスク一覧。変更のたびに userData 経由で永続化し、同日中の再起動で消えないようにする。
    @Published var dailyTasks: [MyTask] = [] {
        didSet { persistDailyTasks() }
    }
    
    // MARK: - UI状態管理
    @Published var needsOnboarding: Bool = true
    @Published var selectedTab: Int = 1
    @Published var needsScheduleRecalculation: Bool = false
    @Published var lastAIGenerationDate: Date? = nil
    
    // ロード・エラー状態管理
    @Published var isLoading: Bool = false
    @Published var connectionError: Bool = false
    
    // MARK: - タスク実行管理
    @Published var activeTaskID: UUID? = nil
    @Published var activeTaskRemainingSeconds: Int = 0
    private var taskTimer: Timer?
    
    // MARK: - アラーム・センサー・省電力
    @Published var isAlarmRinging: Bool = false
    @Published var isSmartAlarmWindow: Bool = false
    @Published var smartAlarmTriggered: Bool = false
    @Published var isFaceDown: Bool = false

    // MARK: - 天気・背景
    @Published var currentTempFeelsLike: String = "--°C"
    @Published var weatherIconName: String = "weather_sunny"
    @Published var backgroundImageName: String = "bg_sunny"
    private var rawWeatherResponse: WeatherResponse?
    @Published var isWeatherIconSystem: Bool = false
    
    
    // MARK: - 睡眠・交通情報
    @Published var lastSleepScore: Int = 0

    // MARK: - 睡眠レポート集計（端末内で完結）
    private(set) var sleepSessionStart: Date? = nil
    private var nightlySnoreCount: Int = 0
    private var nightlyMovementCount: Int = 0
    /// 新しいレポート確定後、朝画面で1回だけモーダルを出すためのフラグ
    @Published var pendingSleepReportModal: Bool = false
    var isBrightBackground: Bool {
            // 明るい背景となるOpenWeatherMapのアイコンコードのリスト
            // ("01d": 晴れ昼, "02d": 晴れ時々曇り昼, "03d": 曇り昼, "04d": 曇り昼, "09d": 霧昼, "10d": 雨昼, "13d": 雪昼, "50d": 霧昼)
        let brightBackgrounds = ["bg_sunny", "bg_cloudy", "bg_rainy"]
                
                // 現在の背景画像が、上のリストに含まれているかチェック
                return brightBackgrounds.contains(backgroundImageName)
            }
    @Published var lastSleepSummary: String? = nil
    @Published var lastSleepAdvice: String? = nil
    @Published var movementThreshold: Double = 1.9
    
    @Published var routeSummary: String = "確認中..."
    @Published var isTrafficDelayDetected: Bool = false
    @Published var estimatedTravelTime: String = "-- 分"
    @Published var isEmergencyScheduleShift: Bool = false
    @Published var emergencyMessage: String = ""
    
    // MARK: - 依存マネージャー
    let locationManager = LocationManager()
    let sensorManager = SensorManager()
    let calendarManager = CalendarManager()
    let soundAnalyzer = SoundAnalyzer()
    
    // 内部変数
    // アプリ固有の固定 UUID（再起動後もキャンセルできるよう定数化）
    let morningAlarmID     = UUID(uuidString: "A3B7C2D1-E4F5-6789-ABCD-EF0123456789")!
    let snoozeGuardAlarmID = UUID(uuidString: "B4C8D3E2-F5A6-789B-CDEF-012345678901")!
    let bedtimeReminderID  = "bedtimeReminder"
    private var alarmEffectsTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?
    private var morningTrafficTimer: Timer?
    private var snoozeGuardTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 初期化
    init() {
        if let loadedData = AppState.loadUserData(appGroupID: appGroupID) {
            self.userData = loadedData
            self.needsOnboarding = false
            if let sound = SleepSoundManager.SleepSound(rawValue: loadedData.selectedSleepSound) {
                self.sleepSoundManager.selectedSound = sound
            }
            // 当日分のタスクを復元（再起動で朝のタスク・完了状態・並び順が消えないように）。
            // 復元できた日は生成済み扱いにして、起動のたびのAI自動再生成（クォータ消費）も防ぐ。
            if loadedData.lastScheduleDate == AppState.dayKey(Date()), !loadedData.dailyTasks.isEmpty {
                self.dailyTasks = loadedData.dailyTasks
                self.lastAIGenerationDate = Date()
            }
        } else {
            self.userData = UserData()
            self.needsOnboarding = true
        }
        setupSensorLink()
        // AudioSession はここでは触らない（起動しただけで他アプリの音楽を止めないため）。
        // アラーム鳴動時 (startAlarmEffects) と録音解析開始時 (SoundAnalyzer) に設定する。
    }

    // "HH:mm" の解析・整形用。端末の12/24時間設定に影響されないよう en_US_POSIX 固定
    static let hhmmFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
    // ==========================================
        // MARK: - フィードバック保存機能
        // ==========================================
        func recordFeedback(taskTitle: String, isGood: Bool) {
            let newFeedback = TaskFeedback(taskTitle: taskTitle, isGood: isGood, date: Date())
            userData.feedbackHistory.append(newFeedback)
            
            // 溜まりすぎ防止: 最新100件だけ残す
            if userData.feedbackHistory.count > 100 {
                userData.feedbackHistory.removeFirst(userData.feedbackHistory.count - 100)
            }
            
            save() // デバイスに保存
            debugLog("📝 フィードバックを保存しました: \(taskTitle) = \(isGood ? "Good" : "Bad")")
        }
    func configureAudioSession() {
            let session = AVAudioSession.sharedInstance()
            do {
                // .playAndRecord: 再生と録音を両立
                // .defaultToSpeaker: 受話口ではなくスピーカーから強制的に音を出す (マナーモード回避の鍵)
                // .allowBluetooth: Bluetoothイヤホン対応
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true)
                debugLog("🔊 AudioSession設定完了: PlayAndRecord + DefaultToSpeaker")
            } catch {
                debugLog("❌ AudioSession設定エラー: \(error)")
            }
        }
    // ==========================================
    // MARK: - スマートスケジュール更新
    // ==========================================
    
    // ==========================================
        // MARK: - スマートスケジュール更新
        // ==========================================
        
        func refreshSmartSchedule(isPremium: Bool, forceRegenerate: Bool = false) async {
            
            await MainActor.run {
                self.isLoading = true
                self.connectionError = false
            }
            debugLog("🧠 [SmartSchedule] 計算を開始します...")
            
            defer {
                Task { @MainActor in
                    self.isLoading = false
                }
            }
            
            // 1. 環境情報の取得
            async let weatherFetch: () = fetchWeatherForCurrentLocation()
            async let eventsFetch = calendarManager.fetchTodayAndTomorrowEvents()
            _ = await weatherFetch
            let events = await eventsFetch
            
            // 2. 出発時間の計算
            let now = Date()
            let upcomingEvents = events.filter { $0.startDate > now && !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
            
            var routineEndDate: Date
            var isBasedOnEvent: Bool = false
            
            if let targetEvent = upcomingEvents.first {
                // パターンA: 予定がある場合
                isBasedOnEvent = true
                var travelSeconds = 1800
                
                if let location = targetEvent.location, !location.isEmpty {
                    let originStr: String
                    if let lat = locationManager.lastKnownLocation?.latitude,
                       let lon = locationManager.lastKnownLocation?.longitude {
                        originStr = "\(lat),\(lon)"
                    } else {
                        originStr = "Current Location"
                    }
                    
                    travelSeconds = await fetchTravelTime(
                        origin: originStr,
                        destination: location,
                        mode: userData.travelMode,
                        isPremium: isPremium
                    )
                }
                routineEndDate = targetEvent.startDate.addingTimeInterval(-Double(travelSeconds))
                
            } else {
                // パターンB: 予定がない場合（ユーザーの起床時間基準）
                isBasedOnEvent = false
                var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
                components.hour = userData.alarmHour
                components.minute = userData.alarmMinute
                
                let alarmDate = Calendar.current.date(from: components) ?? now
                let effectiveAlarmDate = (alarmDate < now.addingTimeInterval(-3600)) ? alarmDate.addingTimeInterval(86400) : alarmDate
                
                // 起床時間から「1時間」のタスクを生成するための目標時刻
                routineEndDate = effectiveAlarmDate.addingTimeInterval(3600)
                
                await MainActor.run {
                    self.routeSummary = "本日の予定なし"
                    self.estimatedTravelTime = "-- 分"
                }
            }
            
            // 3. タスク調整
            await MainActor.run {
                self.adjustTasksForTraffic(newDepartureDate: routineEndDate)
            }
            
            // 4. AI生成判定
            let shouldGenerateAI: Bool
            if forceRegenerate {
                shouldGenerateAI = true
            } else if let lastDate = lastAIGenerationDate, Calendar.current.isDateInToday(lastDate), !dailyTasks.isEmpty {
                shouldGenerateAI = false
            } else {
                shouldGenerateAI = true
            }
            
            if shouldGenerateAI {
                // ★修正: 予定があるかどうか(isBasedOnEvent)のフラグをAI生成処理に渡す
                await updateTasksViaAI(
                    departureTime: routineEndDate,
                    events: events,
                    isPremium: isPremium,
                    isBasedOnEvent: isBasedOnEvent
                )
                await MainActor.run { self.lastAIGenerationDate = Date() }
            }
            
            // 5. 結果の反映
            await MainActor.run {
                if isBasedOnEvent {
                    // 予定がある場合のみ「出発」タスクを追加・更新し、アラーム時間をAIが上書きする
                    let departureTimeStr = AppState.hhmmFormatter.string(from: routineEndDate)
                    
                    if let index = self.dailyTasks.firstIndex(where: { $0.title == "出発" }) {
                        self.dailyTasks[index].time = departureTimeStr
                    } else {
                        let task = MyTask(title: "出発", time: departureTimeStr, duration: "0 min", source: "system")
                        self.dailyTasks.append(task)
                    }
                    
                    let wakeUpDate = routineEndDate.addingTimeInterval(-3600)
                    // 朝の起床時刻として妥当な時間帯(3:00-10:59)のみアラームを上書きする。
                    // 昼夕の予定から逆算した時刻まで設定すると、起床後の再生成で午後に鳴る事故になる。
                    let wakeHour = Calendar.current.component(.hour, from: wakeUpDate)
                    if wakeUpDate > Date(), (3..<11).contains(wakeHour) {
                        let comp = Calendar.current.dateComponents([.hour, .minute], from: wakeUpDate)
                        if let h = comp.hour, let m = comp.minute {
                            self.userData.alarmHour = h
                            self.userData.alarmMinute = m
                            self.userData.isAlarmActive = true
                            self.save()
                        }
                    }
                } else {
                    // 予定がない（休日など）場合は「出発」タスクを消去し、アラーム時間も上書きしない
                    self.dailyTasks.removeAll(where: { $0.title == "出発" })
                }
            }
        }
    
    // ==========================================
    // MARK: - AIタスク生成 (フォールバック実装済み)
    // ==========================================
    
    // ==========================================
        // MARK: - AIタスク生成 (フォールバック実装済み)
        // ==========================================
        
        private func updateTasksViaAI(departureTime: Date, events: [EKEvent], isPremium: Bool, isBasedOnEvent: Bool) async {
            debugLog("🤖 AIタスク生成を開始...")
            
            guard let url = URL(string: "\(serverBaseURL)/suggest_tasks") else {
                debugLog("❌ URL生成失敗 -> フォールバック実行")
                generateFallbackTasks(departureTime: departureTime)
                return
            }
            
            // 天気情報の整形
            var weatherInfoForAI: WeatherInfoForAI? = nil
            if let raw = rawWeatherResponse {
                let main = WeatherInfoForAI.Main(temp: raw.main.temp)
                let weather = raw.weather.map { WeatherInfoForAI.Weather(description: $0.description) }
                weatherInfoForAI = WeatherInfoForAI(main: main, weather: weather)
            }
            
            // カレンダー情報の整形
            let calendarEventsForAI = events.map { event in
                CalendarEventForAI(
                    title: event.title ?? "予定",
                    start: event.startDate.description,
                    end: event.endDate.description
                )
            }
            
            // マスタタスクの整形
            let masterTasksForAI = userData.masterTasks.map { MasterTaskForAI(title: $0) }
            let recentFeedback = userData.feedbackHistory.suffix(10).map {
                        TaskFeedbackForAI(title: $0.taskTitle, is_good: $0.isGood)
                    }
            // ★★★ 修正: 予定がない場合は、AIに出発タスクを作らせないようにプロンプト(文字列)で指示を出す ★★★
            let departureTimeStrForAI: String

            if isBasedOnEvent {
                departureTimeStrForAI = departureTime.description
            } else {
                // Geminiに「予定がない」ことを教え込み、起床時間から1時間で完了するタスクのみを生成させる
                departureTimeStrForAI = "本日は予定なし。出発タスクは不要です。\(AppState.hhmmFormatter.string(from: departureTime))までに完了する約1時間の朝のルーティンを生成してください。"
            }
            
            let reqBody = TaskSuggestionRequest(
                user_name: userData.userName,
                weather_info: weatherInfoForAI,
                sleep_score: lastSleepScore,
                calendar_events: calendarEventsForAI,
                user_master_tasks: masterTasksForAI,
                departure_time: departureTimeStrForAI,
                is_premium: isPremium,
                feedback_history: Array(recentFeedback)
            )
            
            guard let httpBody = try? JSONEncoder().encode(reqBody) else {
                debugLog("❌ JSONエンコード失敗 -> フォールバック実行")
                generateFallbackTasks(departureTime: departureTime)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let token = await getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = httpBody
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    debugLog("⚠️ サーバーエラー -> フォールバック実行")
                    generateFallbackTasks(departureTime: departureTime)
                    return
                }
                
                let suggestedTasks = try JSONDecoder().decode([MyTask].self, from: data)
                
                if suggestedTasks.isEmpty {
                    debugLog("⚠️ AIが空リストを返却 -> フォールバック実行")
                    generateFallbackTasks(departureTime: departureTime)
                    return
                }
                
                await MainActor.run {
                    self.dailyTasks = suggestedTasks
                    // マスタタスク保護
                    for i in 0..<self.dailyTasks.count {
                        if self.userData.masterTasks.contains(self.dailyTasks[i].title) {
                            self.dailyTasks[i].source = "routine"
                        }
                    }
                    debugLog("✅ AIタスク提案を反映しました: \(suggestedTasks.count)件")
                }
                
            } catch {
                debugLog("❌ AI通信エラー: \(error.localizedDescription) -> フォールバック実行")
                generateFallbackTasks(departureTime: departureTime)
            }
        }
    
    // ==========================================
    // MARK: - フォールバック機能 (自力生成)
    // ==========================================
    
    private func generateFallbackTasks(departureTime: Date) {
        debugLog("🛡 フォールバック: マスタタスクからスケジュールを自動生成します")

        // 初期設定直後などマスタタスクが空でも、生成ボタンが行き止まりにならないよう
        // 基本の朝ルーティンを使う。ユーザーのマスタタスク自体は勝手に変更しない。
        let routineTitles = userData.masterTasks.isEmpty
            ? ["洗面", "着替え", "朝食"]
            : userData.masterTasks

        if userData.masterTasks.isEmpty {
            debugLog("ℹ️ マスタタスクが空のため、基本ルーティンでフォールバックします")
        }
        
        var fallbackTasks: [MyTask] = []
        var currentTime = departureTime
        
        // マスタタスクを後ろ（出発直前）から順に配置していく
        for title in routineTitles.reversed() {
            let durationMin = 15 // 仮の所要時間
            let startTime = currentTime.addingTimeInterval(Double(-durationMin * 60))
            
            let task = MyTask(
                title: title,
                time: formatTime(startTime),
                duration: "\(durationMin) min",
                source: "routine"
            )
            
            fallbackTasks.insert(task, at: 0)
            currentTime = startTime
        }
        
        Task { @MainActor in
            self.dailyTasks = fallbackTasks
            debugLog("✅ フォールバック完了: \(fallbackTasks.count)件のタスクを生成")
        }
    }
    
    // ==========================================
    // MARK: - スマート・トラフィック調整
    // ==========================================
    
    func adjustTasksForTraffic(newDepartureDate: Date) {
        guard let currentDepartureTask = dailyTasks.first(where: { $0.title == "出発" }),
              let oldDepartureDate = parseTime(currentDepartureTask.time) else { return }
        
        let diffSeconds = newDepartureDate.timeIntervalSince(oldDepartureDate)
        
        if diffSeconds >= -60 {
            recalculateTaskTimes()
            return
        }
        
        debugLog("🚦 渋滞調整: \(Int(diffSeconds / 60))分 短縮します")
        var secondsToCut = abs(diffSeconds)
        let now = Date()
        
        for i in (0..<dailyTasks.count).reversed() {
            if secondsToCut <= 0 { break }
            var task = dailyTasks[i]
            if task.title == "出発" { continue }
            if task.isCompleted { continue }
            
            if let taskTime = parseTime(task.time), taskTime <= now { continue }
            
            let durationStr = task.duration.replacingOccurrences(of: " min", with: "")
            guard let originalDurationMin = Int(durationStr) else { continue }
            let originalDurationSec = Double(originalDurationMin * 60)
            
            if task.source == "ai" {
                secondsToCut -= originalDurationSec
                dailyTasks.remove(at: i)
                debugLog("   🗑 AIタスク削除: \(task.title)")
            } else {
                if originalDurationSec > 60 {
                    let cutAmount = min(secondsToCut, originalDurationSec - 60)
                    let newDurationMin = Int((originalDurationSec - cutAmount) / 60)
                    dailyTasks[i].duration = "\(newDurationMin) min"
                    secondsToCut -= cutAmount
                    debugLog("   ✂️ ルーティン短縮: \(task.title) -> \(newDurationMin)分")
                }
            }
        }
        recalculateTaskTimes()
    }
    
    func recalculateTaskTimes() {
        guard !dailyTasks.isEmpty else { return }
        
        var runningTime: Date? = nil
        let formatter = AppState.hhmmFormatter

        if let firstTimeStr = dailyTasks.first?.time,
           let date = formatter.date(from: firstTimeStr) {
            
            var comp = Calendar.current.dateComponents([.hour, .minute], from: date)
            let nowComp = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comp.year = nowComp.year; comp.month = nowComp.month; comp.day = nowComp.day
            runningTime = Calendar.current.date(from: comp)
        }
        
        guard var currentTime = runningTime else { return }
        
        for i in 0..<dailyTasks.count {
            dailyTasks[i].time = formatter.string(from: currentTime)
            let durationStr = dailyTasks[i].duration.replacingOccurrences(of: " min", with: "")
            let durationMin = Double(durationStr) ?? 0
            currentTime = currentTime.addingTimeInterval(durationMin * 60)
        }
    }
    
    // ==========================================
    // MARK: - ハイブリッド交通監視
    // ==========================================
    
    func startMorningTrafficMonitoring(isPremium: Bool) {
        stopMorningTrafficMonitoring()
        guard isPremium else { return }
        
        let mode = userData.travelMode
        let interval: TimeInterval = (mode == "transit") ? 900 : 300
        
        debugLog("☀️ [Monitor] 開始: \(mode) / \(Int(interval/60))分間隔")
        
        morningTrafficTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkTrafficDuringRoutine(isPremium: true)
            }
        }
    }
    
    func stopMorningTrafficMonitoring() {
        morningTrafficTimer?.invalidate()
        morningTrafficTimer = nil
    }
    
    private func checkTrafficDuringRoutine(isPremium: Bool) async {
        guard let targetTask = dailyTasks.first(where: { $0.title == "出発" }),
              let currentDepartureTime = parseTime(targetTask.time) else { return }
        
        if Date() > currentDepartureTime {
            stopMorningTrafficMonitoring()
            return
        }
        
        let events = await calendarManager.fetchTodayAndTomorrowEvents()
        guard let targetEvent = events.filter({ $0.startDate > Date() && !$0.isAllDay }).sorted(by: { $0.startDate < $1.startDate }).first,
              let location = targetEvent.location, !location.isEmpty,
              let currentLoc = locationManager.lastKnownLocation else { return }
        
        let originStr = "\(currentLoc.latitude),\(currentLoc.longitude)"
        var newTravelSeconds: Int? = nil
        
        if userData.travelMode == "transit" {
            newTravelSeconds = await fetchTravelTime(origin: originStr, destination: location, mode: "transit", isPremium: true)
        } else {
            newTravelSeconds = await MapKitHelper.calculateTravelTime(from: currentLoc, to: location, mode: userData.travelMode)
        }
        
        guard let travelSeconds = newTravelSeconds else { return }
        let newDepartureDate = targetEvent.startDate.addingTimeInterval(-Double(travelSeconds))
        let diffSeconds = newDepartureDate.timeIntervalSince(currentDepartureTime)
        
        if diffSeconds < -300 {
            await MainActor.run {
                if userData.travelMode == "transit" {
                    self.emergencyMessage = "⚠️ 電車遅延の可能性！早めの行動を"
                    self.isEmergencyScheduleShift = true
                } else {
                    self.adjustTasksForTraffic(newDepartureDate: newDepartureDate)
                    self.emergencyMessage = "⚠️ 渋滞発生！時間を自動調整しました"
                    self.isEmergencyScheduleShift = true
                }
                self.estimatedTravelTime = "\(travelSeconds / 60) 分"
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.isEmergencyScheduleShift = false }
            }
        }
    }
    
    // ==========================================
    // MARK: - スヌーズガード (二度寝防止)
    // ==========================================
    
    func stopAlarm(isPremium: Bool) {
        isAlarmRinging = false
        smartAlarmTriggered = false
        isAlarmFinished = true
        alarmEffectsTask?.cancel()
        audioPlayer?.stop()
        selectedTab = 0
        sensorManager.stopDetection()
        Task { await soundAnalyzer.stopAnalyzing() }
        cancelMorningAlarm()
        // 鳴動中のスヌーズガードアラーム（AlarmKit側）も確実に止める
        try? AlarmManager.shared.stop(id: snoozeGuardAlarmID)
        try? AlarmManager.shared.cancel(id: snoozeGuardAlarmID)
        finalizeSleepReport()
        lastAIGenerationDate = nil
        Task { await refreshSmartSchedule(isPremium: isPremium, forceRegenerate: true) }
        startSnoozeGuard()
    }
    
    // ==========================================
        // MARK: - 最強のスヌーズガード (二度寝防止)
        // ==========================================
    // ==========================================
        // MARK: - スヌーズガード (2度寝防止機能)
        // ==========================================
        
        private func startSnoozeGuard() {
            guard let firstTask = dailyTasks.first else { return }
            guard let startTime = parseTime(firstTask.time) else { return }
            
            let durationMin = extractDurationMinutes(from: firstTask.duration)
            let deadline = startTime.addingTimeInterval(durationMin * 60 + 60)
            let secondsToWait = max(deadline.timeIntervalSince(Date()), 180.0)
            
            debugLog("🛡️ スヌーズガード作動: \(firstTask.title) が \(Int(secondsToWait))秒後 までに終わらなければアラーム再開")

            // 1. 【アプリ終了・画面ロック時の二度寝対策】AlarmKit でアラームを予約
            //    ローカル通知と異なり、おやすみモード貫通・時計アプリ同等の音量で鳴動する
            let snoozeFireDate = Date().addingTimeInterval(secondsToWait)
            Task {
                do {
                    // 前の予約が残っていればキャンセル
                    try? AlarmManager.shared.cancel(id: snoozeGuardAlarmID)

                    let alert = AlarmPresentation.Alert(title: "⚠️ 二度寝していませんか！？")
                    let presentation = AlarmPresentation(alert: alert)
                    let attributes = AlarmAttributes<StelliSeAlarmMetadata>(
                        presentation: presentation,
                        tintColor: .orange
                    )
                    let configuration = AlarmManager.AlarmConfiguration<StelliSeAlarmMetadata>.alarm(
                        schedule: .fixed(snoozeFireDate),
                        attributes: attributes
                    )
                    _ = try await AlarmManager.shared.schedule(id: snoozeGuardAlarmID, configuration: configuration)
                    debugLog("🛡️ AlarmKit: スヌーズガードアラームをセット（\(Int(secondsToWait))秒後）")
                } catch {
                    debugLog("❌ AlarmKit: スヌーズガードのセット失敗: \(error.localizedDescription)")
                }
            }

            // 2. 【アプリを開いたまま二度寝した時用】内部タイマー
            snoozeGuardTask?.cancel()
            snoozeGuardTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: UInt64(secondsToWait * 1_000_000_000))
                    
                    if !Task.isCancelled {
                        if let currentTask = self.dailyTasks.first(where: { $0.id == firstTask.id }), !currentTask.isCompleted {
                            debugLog("🚨 内部スヌーズガード発動！タスク未完了のため強制アラーム！")
                            self.isAlarmRinging = true
                            self.startAlarmEffects()
                        }
                    }
                } catch {
                    // キャンセル時は何もしない
                }
            }
        }
        
        func cancelSnoozeGuardIfNeeded() {
            guard let firstTask = dailyTasks.first else { return }
            if firstTask.isCompleted {
                debugLog("🛑 最初のタスクが完了したため、スヌーズガードを解除します")
                snoozeGuardTask?.cancel()
                snoozeGuardTask = nil
                // AlarmKit のスヌーズガードアラームもキャンセル
                try? AlarmManager.shared.cancel(id: snoozeGuardAlarmID)
            }
        }
   
    
  
    
    // ==========================================
    // MARK: - API通信 (天気・交通)
    // ==========================================
    private func getAuthToken() async -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try? await user.getIDToken()
    }
    
    func fetchTravelTime(origin: String, destination: String, mode: String, isPremium: Bool) async -> Int {
        if !isPremium {
            if let currentLoc = locationManager.lastKnownLocation {
                if let seconds = await MapKitHelper.calculateTravelTime(from: currentLoc, to: destination, mode: mode) {
                    await MainActor.run {
                        self.routeSummary = "予想時間 (MapKit)"
                        self.estimatedTravelTime = "\(seconds / 60) 分"
                    }
                    return seconds
                }
            }
            // 経路が取れなかった場合も「確認中…」のまま放置せず、目安値を表示する
            await MainActor.run {
                self.routeSummary = "経路不明・目安"
                self.estimatedTravelTime = "30 分"
            }
            return 1800
        }
        
        guard let originEnc = origin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let destEnc = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return 1800 }
        
        let urlString = "\(serverBaseURL)/get_travel_time?origin=\(originEnc)&destination=\(destEnc)&mode=\(mode)"
        guard let url = URL(string: urlString) else { return 1800 }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = await getAuthToken() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return 1800 }
            
            struct Response: Decodable { let duration_seconds: Int; let has_delay: Bool; let summary: String }
            let res = try JSONDecoder().decode(Response.self, from: data)
            
            await MainActor.run {
                self.isTrafficDelayDetected = res.has_delay
                self.routeSummary = res.summary
                self.estimatedTravelTime = "\(res.duration_seconds / 60) 分"
            }
            return res.duration_seconds
        } catch { return 1800 }
    }
    
    func fetchWeatherForCurrentLocation() async {
        guard let loc = locationManager.lastKnownLocation else { return }
        let urlString = "\(serverBaseURL)/get_weather?lat=\(loc.latitude)&lon=\(loc.longitude)"
        guard let url = URL(string: urlString) else { return }

        // サーバ側で全エンドポイント認証必須にしているため、天気にもトークンを付ける
        var request = URLRequest(url: url)
        if let token = await getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(WeatherResponse.self, from: data)
            self.rawWeatherResponse = decoded
            
            await MainActor.run {
                            self.currentTempFeelsLike = String(format: "%.1f°C", decoded.main.feels_like)
                            
                            let iconCode = decoded.weather.first?.icon ?? "01d"
                            let isNight = iconCode.hasSuffix("n")
                            
                            // ★★★ 修正: 昼と夜でアイコンの扱いを完全に分ける ★★★
                            self.isWeatherIconSystem = isNight
                            
                            if isNight {
                                // 【夜】 洗練されたシステムアイコンを使用
                                self.backgroundImageName = "image-space-background"
                                if iconCode.contains("09") || iconCode.contains("10") || iconCode.contains("11") {
                                    self.weatherIconName = "cloud.rain.fill"
                                } else if iconCode.contains("03") || iconCode.contains("04") || iconCode.contains("50") {
                                    self.weatherIconName = "cloud.fill"
                                } else if iconCode.contains("13") {
                                    self.weatherIconName = "snowflake"
                                } else {
                                    self.weatherIconName = "moon.stars.fill"
                                }
                            } else {
                                // 【昼】 元のポップで可愛いアセットを使用
                                if iconCode.contains("09") || iconCode.contains("10") || iconCode.contains("11") {
                                    self.backgroundImageName = "bg_rainy"
                                    self.weatherIconName = "weather_rainy" // ※雨の画像名に合わせてください
                                } else if iconCode.contains("03") || iconCode.contains("04") || iconCode.contains("50") {
                                    self.backgroundImageName = "bg_cloudy"
                                    self.weatherIconName = "weather_cloudy" // ※曇りの画像名に合わせてください
                                } else if iconCode.contains("13") {
                                    self.backgroundImageName = "bg_cloudy"
                                    self.weatherIconName = "weather_snow" // ※雪の画像名に合わせてください
                                } else {
                                    self.backgroundImageName = "bg_sunny"
                                    self.weatherIconName = "weather_sunny" // ※晴れの画像名
                                }
                            }
                            
                            debugLog("🌤 天気更新: \(iconCode) -> 昼夜フラグ: \(self.isWeatherIconSystem ? "夜(システム)" : "昼(オリジナル)")")
                        }
        } catch {
            debugLog("❌ 天気取得エラー: \(error)")
        }
    }
    
    // ==========================================
    // MARK: - 保存・読み込み (安全策付き)
    // ==========================================
    
    private static func getSaveURL(appGroupID: String) -> URL? {
        if let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent("my_routines.json") {
            return sharedURL
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("my_routines.json")
    }
    
    /// "yyyy-MM-dd" の日付キー。dailyTasks が「今日の分か」の判定に使う。
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// dailyTasks の変更を userData に写して保存する（didSet から呼ばれる）。
    private func persistDailyTasks() {
        userData.dailyTasks = dailyTasks
        userData.lastScheduleDate = AppState.dayKey(Date())
        save()
    }

    func save() {
        guard let url = AppState.getSaveURL(appGroupID: appGroupID) else { return }
        do {
            let encoded = try JSONEncoder().encode(userData)
            try encoded.write(to: url)
            // アラーム時刻の変更をホーム画面ウィジェットに即反映
            WidgetCenter.shared.reloadAllTimelines()
        } catch { debugLog("❌ 保存エラー: \(error)") }
    }
    
    static func loadUserData(appGroupID: String) -> UserData? {
        guard let url = getSaveURL(appGroupID: appGroupID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserData.self, from: data)
    }

    /// アカウント削除時に端末内の全ユーザーデータを消去する
    func resetAllUserData() {
        userData = UserData()
        dailyTasks = []
        lastSleepScore = 0
        lastSleepSummary = nil
        lastSleepAdvice = nil
        lastAIGenerationDate = nil
        if let url = AppState.getSaveURL(appGroupID: appGroupID) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // ==========================================
    // MARK: - センサー・アラーム・その他
    // ==========================================
    private func setupSensorLink() {
        sensorManager.$isFaceDown
            .receive(on: RunLoop.main)
            .assign(to: \.isFaceDown, on: self)
            .store(in: &cancellables)
            
        sensorManager.onMovementDetected = { [weak self] intensity in
            self?.handleMovement(intensity)
        }
        soundAnalyzer.$lastDetectedSound
                    .receive(on: RunLoop.main)
                    .sink { [weak self] detectedSound in
                        if let sound = detectedSound {
                            self?.handleSoundDetection(sound)
                        }
                    }
                    .store(in: &cancellables)
    }
    
    func handleMovement(_ intensity: Double) {
        // 夜間セッション中は体動を記録（睡眠レポート用）
        if sleepSessionStart != nil { nightlyMovementCount += 1 }

        guard isSmartAlarmWindow, !smartAlarmTriggered else { return }
        if intensity > 2.5 {
            debugLog("💤 浅い睡眠検知 -> スマートアラーム発動")
            smartAlarmTriggered = true
            isAlarmRinging = true
            startAlarmEffects()
        }
    }
    func handleSoundDetection(_ sound: String) {
            // 夜間セッション中はいびきを記録（睡眠レポート用）
            if sound == "Snoring", sleepSessionStart != nil { nightlySnoreCount += 1 }

            guard isSmartAlarmWindow, !smartAlarmTriggered else { return }
            
            // 覚醒の兆候とみなす音
            let triggerSounds = ["Cough", "Speech", "Gasp"]
            
            if triggerSounds.contains(sound) {
                debugLog("🎤 音声検知(\(sound)) -> スマートアラーム発動")
                smartAlarmTriggered = true
                isAlarmRinging = true
                startAlarmEffects()
            }
        }
    
    func finishOnboarding(didLinkCalendar: Bool) async {
        if didLinkCalendar {
            let granted = await calendarManager.requestAccess()
            await MainActor.run { self.userData.calendarLinked = granted }
        } else {
            await MainActor.run { self.userData.calendarLinked = false }
        }
        await MainActor.run {
            self.save()
            withAnimation {
                self.needsOnboarding = false
                self.selectedTab = 1
            }
        }
        // 位置情報はホーム表示「後」に要求する（天気・出発時刻に使う文脈が伝わる位置。
        // ペイウォールや遷移アニメーションに権限ダイアログを重ねない）
        _ = try? await locationManager.requestLocation()
    }
    
    func startNextIncompleteTask(fromIndex index: Int) {
        pauseTaskSequence()
        guard index < dailyTasks.count else { return }
        let task = dailyTasks[index]
        self.activeTaskID = task.id
        
        let durationStr = task.duration.replacingOccurrences(of: " min", with: "")
        let minutes = Int(durationStr) ?? 5
        self.activeTaskRemainingSeconds = minutes * 60
        
        self.taskTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickTaskTimer()
            }
        }
    }
    
    func pauseTaskSequence() {
        taskTimer?.invalidate()
        taskTimer = nil
        self.activeTaskID = nil
    }
    
    private func tickTaskTimer() {
        if activeTaskRemainingSeconds > 0 {
            activeTaskRemainingSeconds -= 1
        } else {
            pauseTaskSequence()
        }
    }
    
    func startAlarmEffects() {
            // 睡眠音を先に止めてからアラーム用セッションを設定
            sleepSoundManager.prepareForAlarm()
            configureAudioSession()

            alarmEffectsTask?.cancel()
            playAlarmSound()
            
            alarmEffectsTask = Task.detached(priority: .userInitiated) {
                while !Task.isCancelled {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    
    private func playAlarmSound() {
        if let soundURL = Bundle.main.url(forResource: "alarm", withExtension: "mp3") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.numberOfLoops = -1
                audioPlayer?.volume = 1.0
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                return
            } catch { }
        }
        AudioServicesPlaySystemSound(1005)
    }
    
    
    func resetNightlyState() async {
        isAlarmRinging = false
        smartAlarmTriggered = false
        isSmartAlarmWindow = false
    }

    // ==========================================
    // MARK: - 睡眠レポート（端末内で算出）
    // ==========================================

    /// 就寝モニタリング開始時に呼ぶ。既にセッション中なら何もしない。
    func startNightSession() {
        guard sleepSessionStart == nil else { return }
        sleepSessionStart = Date()
        nightlySnoreCount = 0
        nightlyMovementCount = 0
        debugLog("🌙 睡眠セッション開始: いびき・体動の記録をリセット")
    }

    /// アラーム停止時に呼ぶ。夜間に集計したいびき・体動からスコアを算出する。
    private func finalizeSleepReport() {
        guard let start = sleepSessionStart else { return }
        sleepSessionStart = nil

        let hours = Date().timeIntervalSince(start) / 3600
        // 就床10分未満（動作確認など）はレポート対象にしない
        guard hours >= (10.0 / 60.0) else { return }

        let movementsPerHour = Double(nightlyMovementCount) / max(hours, 0.1)

        var score = 100
        score -= min(30, Int(movementsPerHour * 3))   // 寝返りが多い＝浅い眠り（最大-30）
        score -= min(20, nightlySnoreCount / 5)       // いびき（最大-20）
        if hours < 6 {
            score -= min(25, Int((6 - hours) * 8))    // 睡眠時間不足（最大-25）
        } else if hours > 9.5 {
            score -= 5                                // 寝すぎ
        }
        lastSleepScore = max(30, min(100, score))

        let hoursText = String(format: "%.1f", hours)
        lastSleepSummary = "就床時間は約\(hoursText)時間。体動を\(nightlyMovementCount)回、いびきを\(nightlySnoreCount)回検知しました。"
        lastSleepAdvice = makeSleepAdvice(hours: hours, movementsPerHour: movementsPerHour, snores: nightlySnoreCount)
        pendingSleepReportModal = true

        debugLog("📊 睡眠レポート確定: score=\(lastSleepScore), 体動=\(nightlyMovementCount), いびき=\(nightlySnoreCount)")
    }

    private func makeSleepAdvice(hours: Double, movementsPerHour: Double, snores: Int) -> String {
        if hours < 6 {
            return "睡眠時間が6時間を下回っています。今夜は30分早く就寝してみましょう。"
        }
        if snores >= 20 {
            return "いびきが多く検知されました。横向きで寝る・寝る前の飲酒を控えるなどを試してみてください。"
        }
        if movementsPerHour >= 8 {
            return "寝返りが多め。寝室の温度や寝具を見直すと、眠りが深くなるかもしれません。"
        }
        return "良い睡眠リズムです。この調子で同じ時刻の就寝・起床を続けましょう。"
    }
    
    // ヘルパー
    // ==========================================
        // MARK: - ヘルパー関数
        // ==========================================
        
    func parseTime(_ timeStr: String) -> Date? {
            guard let date = AppState.hhmmFormatter.date(from: timeStr) else { return nil }
            var comp = Calendar.current.dateComponents([.hour, .minute], from: date)
            let now = Date()
            let nowComp = Calendar.current.dateComponents([.year, .month, .day], from: now)
            comp.year = nowComp.year; comp.month = nowComp.month; comp.day = nowComp.day
            
            guard let parsedDate = Calendar.current.date(from: comp) else { return nil }
            
            // 8時間以上前なら翌日扱い（例: 15:00に "06:00" → 翌朝 06:00）
            if parsedDate.timeIntervalSince(now) < -28800 { // 8時間 = 28800秒
                return parsedDate.addingTimeInterval(86400)
            }
            
            return parsedDate
        }
    
    
    func formatTime(_ date: Date) -> String {
        return AppState.hhmmFormatter.string(from: date)
    }
    
    // ==========================================
        // MARK: - ヘルパー関数
        // ==========================================
        
        // ★追加: task.duration (例: "15 min") から数値(15)だけを抜き出す
        func extractDurationMinutes(from durationStr: String) -> Double {
            let durationText = durationStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Double(durationText) ?? 5.0 // デフォルト5分
        }
    
    
    // ==========================================
    // MARK: - AlarmKit (バックグラウンドアラーム)
    // ==========================================

    /// AlarmKit の使用許可をユーザーに求める
    func requestNotificationPermission() {
        Task {
            do {
                try await AlarmManager.shared.requestAuthorization()
                debugLog("✅ AlarmKit: 許可が得られました")
            } catch {
                debugLog("❌ AlarmKit: 許可エラー: \(error.localizedDescription)")
            }
        }
    }

    /// AlarmKit で朝のアラームをスケジュールする
    func scheduleMorningAlarm() {
        cancelMorningAlarm()
        // アラーム変更のたびに就寝リマインダーも追従させる（アラームOFF時は内部で解除される）
        scheduleBedtimeReminder()
        guard userData.isAlarmActive else { return }

        let calendar = Calendar.current
        var comp = calendar.dateComponents([.year, .month, .day], from: Date())
        comp.hour   = userData.alarmHour
        comp.minute = userData.alarmMinute
        guard let alarmDate = calendar.date(from: comp) else { return }
        let targetDate = alarmDate < Date() ? alarmDate.addingTimeInterval(86400) : alarmDate

        Task {
            do {
                // 未許可の場合はここで権限を要求してから予約
                if AlarmManager.shared.authorizationState != .authorized {
                    let state = try await AlarmManager.shared.requestAuthorization()
                    guard state == .authorized else {
                        debugLog("⚠️ AlarmKit: 権限が得られなかったためアラームを予約しません")
                        return
                    }
                }
                let alert = AlarmPresentation.Alert(title: "⏰ 起きる時間です！")
                let presentation = AlarmPresentation(alert: alert)
                let attributes = AlarmAttributes<StelliSeAlarmMetadata>(
                    presentation: presentation,
                    tintColor: .purple
                )
                let configuration = AlarmManager.AlarmConfiguration<StelliSeAlarmMetadata>.alarm(
                    schedule: .fixed(targetDate),
                    attributes: attributes
                )
                _ = try await AlarmManager.shared.schedule(id: morningAlarmID, configuration: configuration)
                debugLog("✅ AlarmKit: アラームを \(targetDate) にセット完了")
            } catch {
                debugLog("❌ AlarmKit: アラームのセット失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 就寝リマインダー通知をスケジュールする（アラーム時刻の8時間30分前・毎日repeat）
    func scheduleBedtimeReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [bedtimeReminderID])

        guard userData.isBedtimeReminderEnabled, userData.isAlarmActive else { return }

        // アラーム時刻の8時間30分前を算出（日付をまたぐ場合は1440分でラップ）
        let alarmTotalMinutes = userData.alarmHour * 60 + userData.alarmMinute
        let wrappedMinutes = ((alarmTotalMinutes - (8 * 60 + 30)) % 1440 + 1440) % 1440
        let reminderHour = wrappedMinutes / 60
        let reminderMinute = wrappedMinutes % 60
        let alarmHour = userData.alarmHour
        let alarmMinute = userData.alarmMinute

        requestNotificationPermission()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [bedtimeReminderID] granted, error in
            guard granted else {
                if let error = error {
                    debugLog("❌ 就寝リマインダー: 通知権限エラー: \(error.localizedDescription)")
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "そろそろおやすみの時間"
            content.body = String(format: "明日は %02d:%02d 起床。今夜も良い眠りを 🌙", alarmHour, alarmMinute)
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = reminderHour
            dateComponents.minute = reminderMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

            let request = UNNotificationRequest(identifier: bedtimeReminderID, content: content, trigger: trigger)
            center.add(request) { error in
                if let error = error {
                    debugLog("❌ 就寝リマインダー登録失敗: \(error.localizedDescription)")
                } else {
                    debugLog("✅ 就寝リマインダーを \(reminderHour):\(reminderMinute) にセット完了")
                }
            }
        }
    }

    /// スケジュール済みの朝アラームをキャンセルする（同期）
    func cancelMorningAlarm() {
        // 鳴動中(alerting)の場合は stop、予約中の場合は cancel で確実に消す
        try? AlarmManager.shared.stop(id: morningAlarmID)
        do {
            try AlarmManager.shared.cancel(id: morningAlarmID)
        } catch {
            debugLog("⚠️ AlarmKit: アラームキャンセル失敗: \(error.localizedDescription)")
        }
    }
}
