import SwiftUI
import Foundation
import Combine
import EventKit
import AVFoundation
import AudioToolbox
import CoreLocation
import FirebaseAuth
import MapKit
import UserNotifications // ★これをファイルの一番上の方に追加


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
    @Published var dailyTasks: [MyTask] = []
    
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
    
    // アラームミッション用
    @Published var missionNumber1: Int = Int.random(in: 10...99)
    @Published var missionNumber2: Int = Int.random(in: 10...99)
    @Published var missionAnswerText: String = ""
    
    // MARK: - 天気・背景
    @Published var currentTempFeelsLike: String = "--°C"
    @Published var weatherIconName: String = "weather_sunny"
    @Published var backgroundImageName: String = "bg_sunny"
    private var rawWeatherResponse: WeatherResponse?
    @Published var isWeatherIconSystem: Bool = false
    
    
    // MARK: - 睡眠・交通情報
    @Published var lastSleepScore: Int = 0
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
        } else {
            self.userData = UserData()
            self.needsOnboarding = true
        }
        setupSensorLink()
        configureAudioSession()
    }
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
            print("📝 フィードバックを保存しました: \(taskTitle) = \(isGood ? "Good" : "Bad")")
        }
    func configureAudioSession() {
            let session = AVAudioSession.sharedInstance()
            do {
                // .playAndRecord: 再生と録音を両立
                // .defaultToSpeaker: 受話口ではなくスピーカーから強制的に音を出す (マナーモード回避の鍵)
                // .allowBluetooth: Bluetoothイヤホン対応
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
                print("🔊 AudioSession設定完了: PlayAndRecord + DefaultToSpeaker")
            } catch {
                print("❌ AudioSession設定エラー: \(error)")
            }
        }
    // ==========================================
    // MARK: - スマートスケジュール更新
    // ==========================================
    
    // ==========================================
        // MARK: - スマートスケジュール更新
        // ==========================================
        
        func refreshSmartSchedule(isPremium: Bool) async {
            
            await MainActor.run {
                self.isLoading = true
                self.connectionError = false
            }
            print("🧠 [SmartSchedule] 計算を開始します...")
            
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
            if let lastDate = lastAIGenerationDate, Calendar.current.isDateInToday(lastDate), !dailyTasks.isEmpty {
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
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "HH:mm"
                
                if isBasedOnEvent {
                    // 予定がある場合のみ「出発」タスクを追加・更新し、アラーム時間をAIが上書きする
                    let departureTimeStr = timeFormatter.string(from: routineEndDate)
                    
                    if let index = self.dailyTasks.firstIndex(where: { $0.title == "出発" }) {
                        self.dailyTasks[index].time = departureTimeStr
                    } else {
                        let task = MyTask(title: "出発", time: departureTimeStr, duration: "0 min", source: "system")
                        self.dailyTasks.append(task)
                    }
                    
                    let wakeUpDate = routineEndDate.addingTimeInterval(-3600)
                    if wakeUpDate > Date() {
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
            print("🤖 AIタスク生成を開始...")
            
            guard let url = URL(string: "\(serverBaseURL)/suggest_tasks") else {
                print("❌ URL生成失敗 -> フォールバック実行")
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
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let departureTimeStrForAI: String
            
            if isBasedOnEvent {
                departureTimeStrForAI = departureTime.description
            } else {
                // Geminiに「予定がない」ことを教え込み、起床時間から1時間で完了するタスクのみを生成させる
                departureTimeStrForAI = "本日は予定なし。出発タスクは不要です。\(timeFormatter.string(from: departureTime))までに完了する約1時間の朝のルーティンを生成してください。"
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
                print("❌ JSONエンコード失敗 -> フォールバック実行")
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
                    print("⚠️ サーバーエラー -> フォールバック実行")
                    generateFallbackTasks(departureTime: departureTime)
                    return
                }
                
                let suggestedTasks = try JSONDecoder().decode([MyTask].self, from: data)
                
                if suggestedTasks.isEmpty {
                    print("⚠️ AIが空リストを返却 -> フォールバック実行")
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
                    print("✅ AIタスク提案を反映しました: \(suggestedTasks.count)件")
                }
                
            } catch {
                print("❌ AI通信エラー: \(error.localizedDescription) -> フォールバック実行")
                generateFallbackTasks(departureTime: departureTime)
            }
        }
    
    // ==========================================
    // MARK: - フォールバック機能 (自力生成)
    // ==========================================
    
    private func generateFallbackTasks(departureTime: Date) {
        print("🛡 フォールバック: マスタタスクからスケジュールを自動生成します")
        
        guard !userData.masterTasks.isEmpty else {
            print("⚠️ マスタタスクも空です。タスクを生成できません。")
            return
        }
        
        var fallbackTasks: [MyTask] = []
        var currentTime = departureTime
        
        // マスタタスクを後ろ（出発直前）から順に配置していく
        for title in userData.masterTasks.reversed() {
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
            print("✅ フォールバック完了: \(fallbackTasks.count)件のタスクを生成")
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
        
        print("🚦 渋滞調整: \(Int(diffSeconds / 60))分 短縮します")
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
                print("   🗑 AIタスク削除: \(task.title)")
            } else {
                if originalDurationSec > 60 {
                    let cutAmount = min(secondsToCut, originalDurationSec - 60)
                    let newDurationMin = Int((originalDurationSec - cutAmount) / 60)
                    dailyTasks[i].duration = "\(newDurationMin) min"
                    secondsToCut -= cutAmount
                    print("   ✂️ ルーティン短縮: \(task.title) -> \(newDurationMin)分")
                }
            }
        }
        recalculateTaskTimes()
    }
    
    func recalculateTaskTimes() {
        guard !dailyTasks.isEmpty else { return }
        
        var runningTime: Date? = nil
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
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
        
        print("☀️ [Monitor] 開始: \(mode) / \(Int(interval/60))分間隔")
        
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
    
    func stopAlarm() {
        isAlarmRinging = false
        smartAlarmTriggered = false
        isAlarmFinished = true
        alarmEffectsTask?.cancel()
        audioPlayer?.stop()
        selectedTab = 0
        sensorManager.stopDetection()
                Task { await soundAnalyzer.stopAnalyzing() }
        missionAnswerText = ""
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["MorningAlarm"])
        Task { await refreshSmartSchedule(isPremium: false) }
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
            
            print("🛡️ スヌーズガード作動: \(firstTask.title) が \(Int(secondsToWait))秒後 までに終わらなければアラーム再開")
            
            // 1. 【画面ロック(2度寝)対策】 OSにスヌーズアラームを予約する
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted {
                    let content = UNMutableNotificationContent()
                    content.title = "⚠️ 2度寝していませんか！？"
                    content.body = "最初のタスク「\(firstTask.title)」が終わっていません！今すぐ起きてください！"
                    
                    // ★ 普通の「ピコン」という通知音ではなく、あの大音量アラームを指定！
                    content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.mp3"))
                    
                    // ★ 即時通知にしておやすみモードを貫通させる
                    if #available(iOS 15.0, *) {
                        content.interruptionLevel = .timeSensitive
                    }
                    
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: secondsToWait, repeats: false)
                    let request = UNNotificationRequest(identifier: "SnoozeGuardAlert", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request)
                }
            }
            
            // 2. 【アプリを開いたまま2度寝した時用】 内部タイマー
            snoozeGuardTask?.cancel()
            snoozeGuardTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: UInt64(secondsToWait * 1_000_000_000))
                    
                    if !Task.isCancelled {
                        if let currentTask = self.dailyTasks.first(where: { $0.id == firstTask.id }), !currentTask.isCompleted {
                            print("🚨 内部スヌーズガード発動！タスク未完了のため強制アラーム！")
                            self.generateNewMission()
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
                print("🛑 最初のタスクが完了したため、スヌーズガードを解除します")
                snoozeGuardTask?.cancel()
                snoozeGuardTask = nil
                
                // ★★★ 追加: タスクを完了したら、OSに予約した2度寝防止アラームも確実に消去する ★★★
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["SnoozeGuardAlert"])
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
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
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
                            
                            print("🌤 天気更新: \(iconCode) -> 昼夜フラグ: \(self.isWeatherIconSystem ? "夜(システム)" : "昼(オリジナル)")")
                        }
        } catch {
            print("❌ 天気取得エラー: \(error)")
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
    
    func save() {
        guard let url = AppState.getSaveURL(appGroupID: appGroupID) else { return }
        do {
            let encoded = try JSONEncoder().encode(userData)
            try encoded.write(to: url)
        } catch { print("❌ 保存エラー: \(error)") }
    }
    
    static func loadUserData(appGroupID: String) -> UserData? {
        guard let url = getSaveURL(appGroupID: appGroupID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserData.self, from: data)
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
        guard isSmartAlarmWindow, !smartAlarmTriggered else { return }
        if intensity > 2.5 {
            print("💤 浅い睡眠検知 -> スマートアラーム発動")
            smartAlarmTriggered = true
            isAlarmRinging = true
            startAlarmEffects()
        }
    }
    func handleSoundDetection(_ sound: String) {
            guard isSmartAlarmWindow, !smartAlarmTriggered else { return }
            
            // 覚醒の兆候とみなす音
            let triggerSounds = ["Cough", "Speech", "Gasp"]
            
            if triggerSounds.contains(sound) {
                print("🎤 音声検知(\(sound)) -> スマートアラーム発動")
                generateNewMission()
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
            // ★★★ 修正: アラーム鳴動時にも設定を強制適用 (他のアプリに設定を変えられた場合の対策)
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
    
    func generateNewMission() {
        missionNumber1 = Int.random(in: 10...99)
        missionNumber2 = Int.random(in: 10...99)
        missionAnswerText = ""
    }
    
    func checkMissionAnswer() -> Bool {
        let input = Int(missionAnswerText) ?? -999
        return input == (missionNumber1 + missionNumber2)
    }
    
    func resetNightlyState() async {
        isAlarmRinging = false
        smartAlarmTriggered = false
        isSmartAlarmWindow = false
    }
    
    // ヘルパー
    // ==========================================
        // MARK: - ヘルパー関数
        // ==========================================
        
    func parseTime(_ timeStr: String) -> Date? {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            guard let date = formatter.date(from: timeStr) else { return nil }
            var comp = Calendar.current.dateComponents([.hour, .minute], from: date)
            let now = Date()
            let nowComp = Calendar.current.dateComponents([.year, .month, .day], from: now)
            comp.year = nowComp.year; comp.month = nowComp.month; comp.day = nowComp.day
            
            guard let parsedDate = Calendar.current.date(from: comp) else { return nil }
            
            // ★★★ 修正: もし計算した時間が「現在時刻より12時間以上前（過去）」なら、明日の予定とみなす ★★★
            if parsedDate.timeIntervalSince(now) < -43200 { // 12時間 = 43200秒
                return parsedDate.addingTimeInterval(86400) // 1日（86400秒）足す
            }
            
            return parsedDate
        }
    
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
        // MARK: - ローカル通知 (バックグラウンドアラーム)
        // ==========================================
        
        /// 通知の許可をユーザーに求める
        func requestNotificationPermission() {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if granted {
                    print("✅ 通知の許可が得られました")
                } else if let error = error {
                    print("❌ 通知の許可エラー: \(error.localizedDescription)")
                }
            }
        }
        
        /// OSレベルで明日の朝のアラームを予約する
        func scheduleMorningAlarm() {
            // まず古いアラーム予約をすべてキャンセルする
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["MorningAlarm"])
            
            // アラームがオフならここで終了
            guard userData.isAlarmActive else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "⏰ 起きる時間です！"
            content.body = "Stelliseを開いて、朝のミッションをクリアしましょう。"
            
            // ★重要: Xcodeに追加したアラーム音のファイル名(拡張子含む)に必ず合わせること
            // 30秒以下の音声ファイルである必要があります。
            content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.mp3"))
            if #available(iOS 15.0, *) {
                        content.interruptionLevel = .timeSensitive
                    }
            // 目標時刻の計算
            let calendar = Calendar.current
            var comp = calendar.dateComponents([.year, .month, .day], from: Date())
            comp.hour = userData.alarmHour
            comp.minute = userData.alarmMinute
            
            guard let alarmDate = calendar.date(from: comp) else { return }
            
            // すでに今日のその時間を過ぎているなら明日にする
            let targetDate = alarmDate < Date() ? alarmDate.addingTimeInterval(86400) : alarmDate
            
            let triggerComp = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComp, repeats: false)
            
            let request = UNNotificationRequest(identifier: "MorningAlarm", content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ バックグラウンドアラームのセット失敗: \(error)")
                } else {
                    print("✅ バックグラウンドアラームを \(targetDate) にセット完了！")
                }
            }
        }
}
