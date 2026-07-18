import Foundation
import SwiftUI

struct SleepReport: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    let date: Date
    let startDate: Date
    let endDate: Date
    let score: Int
    let movementCount: Int
    let snoreCount: Int
    let summary: String
    let advice: String

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
}

// クラスの外側（トップレベル）に定義
struct UserData: Codable, Sendable {
    // ※身長・体重の入力は廃止（睡眠解析ロジックで未使用だったため。
    //   過去バージョンの保存JSONに残っていてもデコード時に無視されるだけで安全）
    var bedFirmness: Double = 50.0
    var movementThreshold: Double = 1.9
    var homeAddress: String = ""
    var lastScheduleDate: String = ""
    
    var masterTasks: [String] = []
    var dailyTasks: [MyTask] = []
    
    var alarmHour: Int = 6
    var alarmMinute: Int = 45
    var isAlarmActive: Bool = true
    
    var travelMode: String = "transit"
    var calendarLinked: Bool = false
    var isSmartAlarmEnabled: Bool = true
    var selectedSleepSound: String = "焚き火"
    var feedbackHistory: [TaskFeedback] = []
    // Optionalなので過去バージョンの保存データもそのまま読める
    var lastReviewRequestDate: Date? = nil
    // 就寝リマインダー通知のON/OFF（新規追加。旧保存データにキーが無くてもデフォルトtrueで読める）
    var isBedtimeReminderEnabled: Bool = true
    var sleepReports: [SleepReport] = []
    var sleepSessionStart: Date? = nil
    var nightlySnoreCount: Int = 0
    var nightlyMovementCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case bedFirmness, movementThreshold, homeAddress, lastScheduleDate
        case masterTasks, dailyTasks
        case alarmHour, alarmMinute, isAlarmActive
        case travelMode, calendarLinked, isSmartAlarmEnabled, selectedSleepSound, feedbackHistory
        case lastReviewRequestDate
        case isBedtimeReminderEnabled
        case sleepReports, sleepSessionStart, nightlySnoreCount, nightlyMovementCount
    }

    init() {}

    // 単純なCodable自動合成だとキー欠落時にデコード全体が失敗してしまう（＝旧バージョンのJSONに
    // isBedtimeReminderEnabledが無いだけで保存データが丸ごと初期化される）ため、
    // MyTaskと同様にdecodeIfPresent + デフォルト値で後方互換を担保する
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.bedFirmness = (try? container.decodeIfPresent(Double.self, forKey: .bedFirmness)) ?? 50.0
        self.movementThreshold = (try? container.decodeIfPresent(Double.self, forKey: .movementThreshold)) ?? 1.9
        self.homeAddress = (try? container.decodeIfPresent(String.self, forKey: .homeAddress)) ?? ""
        self.lastScheduleDate = (try? container.decodeIfPresent(String.self, forKey: .lastScheduleDate)) ?? ""
        self.masterTasks = (try? container.decodeIfPresent([String].self, forKey: .masterTasks)) ?? []
        self.dailyTasks = (try? container.decodeIfPresent([MyTask].self, forKey: .dailyTasks)) ?? []
        self.alarmHour = (try? container.decodeIfPresent(Int.self, forKey: .alarmHour)) ?? 6
        self.alarmMinute = (try? container.decodeIfPresent(Int.self, forKey: .alarmMinute)) ?? 45
        self.isAlarmActive = (try? container.decodeIfPresent(Bool.self, forKey: .isAlarmActive)) ?? true
        self.travelMode = (try? container.decodeIfPresent(String.self, forKey: .travelMode)) ?? "transit"
        self.calendarLinked = (try? container.decodeIfPresent(Bool.self, forKey: .calendarLinked)) ?? false
        self.isSmartAlarmEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isSmartAlarmEnabled)) ?? true
        self.selectedSleepSound = (try? container.decodeIfPresent(String.self, forKey: .selectedSleepSound)) ?? "焚き火"
        self.feedbackHistory = (try? container.decodeIfPresent([TaskFeedback].self, forKey: .feedbackHistory)) ?? []
        self.lastReviewRequestDate = (try? container.decodeIfPresent(Date.self, forKey: .lastReviewRequestDate)) ?? nil
        self.isBedtimeReminderEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .isBedtimeReminderEnabled)) ?? true
        self.sleepReports = (try? container.decodeIfPresent([SleepReport].self, forKey: .sleepReports)) ?? []
        self.sleepSessionStart = (try? container.decodeIfPresent(Date.self, forKey: .sleepSessionStart)) ?? nil
        self.nightlySnoreCount = (try? container.decodeIfPresent(Int.self, forKey: .nightlySnoreCount)) ?? 0
        self.nightlyMovementCount = (try? container.decodeIfPresent(Int.self, forKey: .nightlyMovementCount)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bedFirmness, forKey: .bedFirmness)
        try container.encode(movementThreshold, forKey: .movementThreshold)
        try container.encode(homeAddress, forKey: .homeAddress)
        try container.encode(lastScheduleDate, forKey: .lastScheduleDate)
        try container.encode(masterTasks, forKey: .masterTasks)
        try container.encode(dailyTasks, forKey: .dailyTasks)
        try container.encode(alarmHour, forKey: .alarmHour)
        try container.encode(alarmMinute, forKey: .alarmMinute)
        try container.encode(isAlarmActive, forKey: .isAlarmActive)
        try container.encode(travelMode, forKey: .travelMode)
        try container.encode(calendarLinked, forKey: .calendarLinked)
        try container.encode(isSmartAlarmEnabled, forKey: .isSmartAlarmEnabled)
        try container.encode(selectedSleepSound, forKey: .selectedSleepSound)
        try container.encode(feedbackHistory, forKey: .feedbackHistory)
        try container.encode(lastReviewRequestDate, forKey: .lastReviewRequestDate)
        try container.encode(isBedtimeReminderEnabled, forKey: .isBedtimeReminderEnabled)
        try container.encode(sleepReports, forKey: .sleepReports)
        try container.encode(sleepSessionStart, forKey: .sleepSessionStart)
        try container.encode(nightlySnoreCount, forKey: .nightlySnoreCount)
        try container.encode(nightlyMovementCount, forKey: .nightlyMovementCount)
    }
}

// ★ 修正: 'Equatable' を追加しました
struct MyTask: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var title: String
    var time: String
    var duration: String
    var source: String
    var isCompleted: Bool
    
    enum CodingKeys: String, CodingKey {
        case title, time, duration, source, isCompleted
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.time = try container.decode(String.self, forKey: .time)
        self.duration = try container.decode(String.self, forKey: .duration)
        self.source = try container.decode(String.self, forKey: .source)
        self.isCompleted = (try? container.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        self.id = UUID()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.time, forKey: .time)
        try container.encode(self.duration, forKey: .duration)
        try container.encode(self.source, forKey: .source)
        try container.encode(self.isCompleted, forKey: .isCompleted)
    }
    
    init(id: UUID = UUID(), title: String, time: String, duration: String, source: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.time = time
        self.duration = duration
        self.source = source
        self.isCompleted = isCompleted
    }
    
    // Equatable準拠 (IDが同じなら同じとみなす)
    static func == (lhs: MyTask, rhs: MyTask) -> Bool {
        return lhs.id == rhs.id && lhs.isCompleted == rhs.isCompleted
    }
    
    var iconName: String {
            switch source {
            case "routine", "manual": return "person.fill"  // ユーザーの意思
            case "ai":                return "sparkles"     // AIの提案
            case "system":            return "car.fill"     // 出発
            default:                  return "circle"
            }
        }
        
        var iconColor: Color {
            switch source {
            case "routine", "manual": return .blue
            case "ai":                return .purple
            case "system":            return .red
            default:                  return .gray
            }
        }
}
