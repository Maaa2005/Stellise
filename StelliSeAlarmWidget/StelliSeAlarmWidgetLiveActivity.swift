import AlarmKit
import ActivityKit
import WidgetKit
import SwiftUI

// 本体(AppState.swift)と同じ空の Metadata 型（AlarmKit の型引数として必要）
struct StelliSeAlarmMetadata: AlarmMetadata {}

struct StelliSeAlarmWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<StelliSeAlarmMetadata>.self) { context in
            // ロック画面 / 通知バナー表示
            HStack(spacing: 16) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text("⏰ 起きる時間です！")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Stellise を開いてミッションをクリアしてください")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.9))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("起きる時間です！")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Stellise を開いてミッションをクリア")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Text("⏰")
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.purple)
            }
        }
    }
}
