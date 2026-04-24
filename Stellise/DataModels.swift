import Foundation
import SwiftUI

// クラスの外側（トップレベル）に定義
struct UserData: Codable, Sendable {
    var userName: String = ""
    var userHeight: String = ""
    var userWeight: String = ""
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
    var feedbackHistory: [TaskFeedback] = []
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
