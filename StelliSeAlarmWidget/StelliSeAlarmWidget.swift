//
//  StelliSeAlarmWidget.swift
//  StelliSeAlarmWidget
//
//  ホーム画面ウィジェット: 次のアラーム時刻を表示する。
//  本体アプリが App Group (group.com.stellise) に保存する my_routines.json を読む。
//

import WidgetKit
import SwiftUI

// MARK: - 共有データの読み込み

/// 本体の UserData のうち、ウィジェットに必要な項目だけを読むための軽量ミラー
private struct SharedAlarmData: Decodable {
    var alarmHour: Int
    var alarmMinute: Int
    var isAlarmActive: Bool
}

private func loadSharedAlarmData() -> SharedAlarmData? {
    guard let url = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: "group.com.stellise")?
        .appendingPathComponent("my_routines.json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(SharedAlarmData.self, from: data)
}

// MARK: - Timeline

struct AlarmEntry: TimelineEntry {
    let date: Date
    let alarmTimeText: String?   // "06:45" / nil = 未設定
    let isActive: Bool
}

struct AlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlarmEntry {
        AlarmEntry(date: Date(), alarmTimeText: "06:45", isActive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        // アラーム時刻はアプリ側の保存時にしか変わらないため、1時間ごとの再読込で十分
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [makeEntry()], policy: .after(refresh)))
    }

    private func makeEntry() -> AlarmEntry {
        if let shared = loadSharedAlarmData() {
            let text = String(format: "%02d:%02d", shared.alarmHour, shared.alarmMinute)
            return AlarmEntry(date: Date(), alarmTimeText: text, isActive: shared.isAlarmActive)
        }
        return AlarmEntry(date: Date(), alarmTimeText: nil, isActive: false)
    }
}

// MARK: - View

struct StelliSeAlarmWidgetEntryView: View {
    var entry: AlarmEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            // ロック画面用: モノクロで簡潔に
            HStack(spacing: 6) {
                Image(systemName: entry.isActive ? "alarm.fill" : "alarm")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Stellise")
                        .font(.caption2)
                    Text(displayText)
                        .font(.headline.monospacedDigit())
                }
            }
        default:
            // ホーム画面 systemSmall: アプリと同じ紺×ラベンダーのトーン
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: entry.isActive ? "alarm.fill" : "alarm")
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.71, green: 0.66, blue: 1.0))
                    Text("次のアラーム")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text(displayText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.isActive ? "スマート起床 待機中" : "アラームはオフです")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var displayText: String {
        guard let time = entry.alarmTimeText else { return "未設定" }
        return entry.isActive ? time : "\(time)（オフ）"
    }
}

// MARK: - Widget

struct StelliSeAlarmWidget: Widget {
    let kind: String = "StelliSeAlarmWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AlarmProvider()) { entry in
            StelliSeAlarmWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.11, green: 0.11, blue: 0.23),
                                 Color(red: 0.04, green: 0.04, blue: 0.08)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("次のアラーム")
        .description("Stellise の起床アラーム時刻を表示します。")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    StelliSeAlarmWidget()
} timeline: {
    AlarmEntry(date: .now, alarmTimeText: "06:45", isActive: true)
    AlarmEntry(date: .now, alarmTimeText: nil, isActive: false)
}
