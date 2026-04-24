import Foundation
import EventKit

class CalendarManager {
    
    let eventStore = EKEventStore()

    // 1. ユーザーに「アクセス許可」をリクエストする関数
    func requestAccess() async -> Bool {
        
        // ★★★ 修正 (iOS 17 Deprecation 対策) ★★★
        // 古い requestAccess(to:) は completion handler ベースの
        // requestFullAccessToEvents に置き換える必要があります。
        // withCheckedContinuation は、古い形式を async/await に「変換」する定型文です。
        return await withCheckedContinuation { continuation in
            eventStore.requestFullAccessToEvents { (granted, error) in
                if let error = error {
                    print("【CalendarManager】アクセスリクエスト中にエラー: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    if granted {
                        print("【CalendarManager】カレンダー（フルアクセス）が許可されました。")
                    } else {
                        print("【CalendarManager】カレンダー（フルアクセス）が拒否されました。")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
        // ★★★ 修正ここまで ★★★
    }
    
    // 2. 「今日」と「明日」のイベントを取得する関数
    func fetchTodayAndTomorrowEvents() async -> [EKEvent] {
        
        // ★★★ 修正 (iOS 17 Deprecation 対策) ★★★
        // 古い .authorized の代わりに .fullAccess をチェックします
        let status = EKEventStore.authorizationStatus(for: .event)
        
        guard status == .fullAccess else {
            print("【CalendarManager】カレンダーのフルアクセス許可がありません。イベントを取得できません。")
            if status == .writeOnly {
                 print("【CalendarManager】書き込み専用アクセスのみ許可されています。読み取りはできません。")
            }
            return [] // 許可がない場合は空の配列を返す
        }
        // ★★★ 修正ここまで ★★★
        
        // 取得するカレンダー（デバイス上のすべてのカレンダー）
        let calendars = eventStore.calendars(for: .event)
        
        // 検索範囲（今から48時間後まで）
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 2, to: startDate)!
        
        // 検索条件を作成
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        
        // イベントを検索
        let events = eventStore.events(matching: predicate)
        
        print("【CalendarManager】\(events.count)件のイベントを取得しました。")
        return events
    }
}
