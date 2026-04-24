import SwiftUI

struct TaskRowView: View {
    @Binding var task: MyTask
    var onFeedbackGood: () -> Void
    var onFeedbackBad: () -> Void
    
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var appState: AppState
    
    @State private var hasGivenFeedback: Bool = false
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let startTime = appState.parseTime(task.time) ?? Date()
            let durationMinutes = appState.extractDurationMinutes(from: task.duration)
            let deadline = startTime.addingTimeInterval(durationMinutes * 60)
            let remainingSeconds = deadline.timeIntervalSince(context.date)
            
            // ★★★ 修正: タスクの開始時刻を過ぎているかどうかの判定を追加 ★★★
            let hasStarted = context.date >= startTime
            
            // 開始していて、かつ残り1分未満のときだけ警告モードにする
            let isWarning = hasStarted && remainingSeconds < 60
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    let remainingText: String = {
                        if !hasStarted {
                            // ★ まだ開始時刻が来ていない未来のタスクは、元の文字(15 minなど)をそのまま表示
                            return task.duration
                        } else if remainingSeconds >= 60 {
                            // 実行中 (残り1分以上)
                            let minutes = Int(remainingSeconds / 60)
                            return "\(minutes) min"
                        } else if remainingSeconds > 0 {
                            // 実行中 (残り1分未満、秒単位で焦らせる)
                            let seconds = Int(remainingSeconds)
                            return String(format: "0:%02d", seconds)
                        } else {
                            // 期限切れ
                            return "遅刻"
                        }
                    }()
                    
                    Text("\(task.time) • \(remainingText)")
                        .font(.subheadline)
                        .foregroundStyle(isWarning ? .red : .secondary)
                }
                Spacer()
                
                // AIフィードバックボタン
                if task.source == "ai" {
                    if hasGivenFeedback {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.8))
                            .font(.title3)
                            .padding(.trailing, 8)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        HStack(spacing: 16) {
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                onFeedbackGood()
                                withAnimation(.spring()) { hasGivenFeedback = true }
                            }) {
                                Image(systemName: "hand.thumbsup")
                                    .foregroundStyle(.primary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                onFeedbackBad()
                                withAnimation(.spring()) { hasGivenFeedback = true }
                            }) {
                                Image(systemName: "hand.thumbsdown")
                                    .foregroundStyle(.primary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.title3)
                        .padding(.trailing, 8)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            // 警告モードの時だけ赤枠と拡大アニメーションを適用
            .scaleEffect(isWarning ? 1.05 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isWarning ? Color.red : Color.clear, lineWidth: isWarning ? 2 : 0)
            )
            .animation(.easeInOut(duration: 0.3), value: isWarning)
        }
    }
}
