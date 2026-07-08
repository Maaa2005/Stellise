import SwiftUI
import EventKit
import StoreKit

struct DayView: View {

    @EnvironmentObject var appState: AppState
    @State private var isShowingReportModal: Bool = false
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.requestReview) private var requestReview
    
    private var allTasksCompleted: Bool {
        !appState.dailyTasks.isEmpty && appState.dailyTasks.allSatisfy { $0.isCompleted }
    }
    private var dateString: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月d日 EEEE"
            return formatter.string(from: Date())
        }

    /// 昨夜の睡眠スコアに応じた朝の一言。低スコアでも警告・ダメ出しはしない。
    private var sleepMoodLine: String {
        switch appState.lastSleepScore {
        case 80...: return "ぐっすり眠れました。今日は攻めていける日です"
        case 60..<80: return "まずまずの睡眠。いつものペースでいきましょう"
        default: return "少し寝不足気味。今日は無理せずいきましょう"
        }
    }

    /// 全タスク完了の瞬間にApp Storeレビューを依頼する（30日に1回まで）
    private func requestReviewIfAppropriate() {
        let thirtyDays: TimeInterval = 30 * 24 * 3600
        if let last = appState.userData.lastReviewRequestDate,
           Date().timeIntervalSince(last) < thirtyDays {
            return
        }
        appState.userData.lastReviewRequestDate = Date()
        appState.save()
        requestReview()
    }
    
    var body: some View {
            ZStack {
                // 背景は StelliseApp の共有 Background3DView（朝⇄夜で連続）。ここでは持たない。

                // --- コンテンツ ---
                if appState.isLoading {
                    // ローディング画面
                    ZStack {
                        Color.black.opacity(0.4).edgesIgnoringSafeArea(.all)
                        VStack(spacing: 24) {
                            ProgressView()
                                .scaleEffect(1.2)
                                .tint(.white)
                            Text("スケジュールを作成中...")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .cornerRadius(24)
                    }
                    .zIndex(10)
                    
                } else if appState.connectionError {
                    // 通信エラー画面
                    VStack(spacing: 20) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("通信エラーが発生しました")
                            .font(.headline)
                            .foregroundStyle(.white)
                        
                        Button(action: {
                            Task {
                                await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium)
                            }
                        }) {
                            Text("再試行")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.6))
                    .zIndex(9)
                    
                } else {
                    // 通常画面
                    VStack(spacing: 0) {
                        // 緊急バナー
                        if appState.isEmergencyScheduleShift {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.callout)
                                Text(appState.emergencyMessage)
                                    .font(.callout)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            // 真っ赤は朝から不安を煽るので、遅刻警告と同じ暖色オレンジで統一
                            .background(Color(red: 1.0, green: 0.55, blue: 0.15).opacity(0.9))
                        }
                        
                        // ヘッダー
                        // ヘッダー
                                            HeaderView(
                                                departureTime: appState.dailyTasks.first(where: { $0.title == "出発" })?.time ?? "--:--",
                                                travelTime: appState.estimatedTravelTime,
                                                feelsLikeTemp: appState.currentTempFeelsLike,
                                                iconName: appState.weatherIconName,
                                                isWeatherIconSystem: appState.isWeatherIconSystem, // ★★★ 追加 ★★★
                                                travelMode: appState.userData.travelMode,
                                                routeSummary: appState.routeSummary,
                                                isDelay: appState.isTrafficDelayDetected,
                                                isBright: appState.isBrightBackground // 背景の明暗でガラス/文字色を切替
                                            )
                        
                        // --- 時計 (スマート・ミニマルスタイル) ---
                        VStack(spacing: 0) {
                            // 時間
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                Text(context.date, style: .time)
                                    // P0: デザイントークンの大時計フォント（rounded + monospacedDigit）
                                    .font(Theme.Typography.clock(96))
                                    // 背景が明るい時は濃紺、暗い時は白
                                    .foregroundStyle(appState.isBrightBackground ? Theme.Palette.textOnBright : Theme.Palette.textOnDark)
                                    // 雲や空の濃淡で数字が埋もれないよう、背景の逆方向にソフトな影/ハローを敷く
                                    .shadow(color: appState.isBrightBackground ? .white.opacity(0.55) : .black.opacity(0.4),
                                            radius: appState.isBrightBackground ? 12 : 7, y: 1)
                            }

                            // 日付
                            Text(dateString)
                                .font(.system(.title3, design: .rounded, weight: .regular))
                                .tracking(3)
                                // 背景が明るい時は濃紺、暗い時は白
                                .foregroundStyle(appState.isBrightBackground ? Theme.Palette.textOnBright.opacity(0.8) : Theme.Palette.textOnDarkMuted)
                                .shadow(color: appState.isBrightBackground ? .white.opacity(0.5) : .black.opacity(0.35),
                                        radius: appState.isBrightBackground ? 8 : 5, y: 1)

                            // 昨夜の睡眠に寄り添う一言。スコアが低くても責めない（常にポジティブ）
                            if appState.lastSleepScore > 0 {
                                Text(sleepMoodLine)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(appState.isBrightBackground ? Theme.Palette.textOnBright.opacity(0.65) : Theme.Palette.textOnDarkMuted.opacity(0.8))
                                    .shadow(color: appState.isBrightBackground ? .white.opacity(0.4) : .black.opacity(0.3), radius: 4, y: 1)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(.vertical, 24)
                        
                        // タスクリスト
                        if appState.dailyTasks.isEmpty {
                            Spacer()
                            // タスク未生成: 自動生成せず、手動で生成させる
                            VStack(spacing: 18) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 44, weight: .ultraLight))
                                    .foregroundStyle(.white)
                                Text("今日のタスクはまだありません")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("天気と予定から、出発に間に合う\n朝のルーティンを組み立てます。")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineSpacing(4)
                                Button {
                                    let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
                                    Task { await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium) }
                                } label: {
                                    Text("タスクを生成")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 32)
                                        .padding(.vertical, 14)
                                        .background(Color.appAccent, in: Capsule())
                                }
                                .padding(.top, 4)
                            }
                            .padding(40)
                            .glassCard()
                            .padding(.horizontal, 32)
                            Spacer()

                        } else if allTasksCompleted {
                            Spacer()
                            // 完了画面
                            VStack(spacing: 16) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 60, weight: .ultraLight))
                                    .foregroundStyle(.white)

                                Text("準備完了")
                                    .font(.title3)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)

                                Text("すべてのタスクが完了しました。\n今日も良い一日を。")
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineSpacing(4)
                            }
                            .padding(40)
                            .background(.ultraThinMaterial)
                            .cornerRadius(32)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            // 「準備完了」= ユーザー体験のピークでレビューを依頼（30日に1回まで）
                            .onAppear { requestReviewIfAppropriate() }
                            Spacer()
                            
                        } else {
                            // コンパクトなタスク一覧。タップで完了、ドラッグで並び替え。
                            VStack(spacing: 12) {
                                TaskListView(
                                    onFeedbackGood: { task in appState.recordFeedback(taskTitle: task.title, isGood: true) },
                                    onFeedbackBad: { task in appState.recordFeedback(taskTitle: task.title, isGood: false) }
                                )
                                .padding(.horizontal, 16)

                                Spacer()

                                Text("AIは間違えることがあります。重要な情報は確認してください。")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.bottom, 12)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: allTasksCompleted)
                }
            }

            .onAppear {
            // タスクは自動生成しない（アラーム発火 or 手動「生成」ボタンで作る）
            // レポートモーダルは「新しいレポートが出た直後の1回だけ」表示する
            // （以前は lastSleepScore > 0 の間、タブを切り替えるたびに再表示されていた）
            if appState.pendingSleepReportModal {
                appState.pendingSleepReportModal = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isShowingReportModal = true }
            }
            if appState.lastSleepScore > 0 {
                appState.startMorningTrafficMonitoring(isPremium: subscriptionManager.isPremium)
            }
        }
        .onDisappear {
            appState.stopMorningTrafficMonitoring()
        }
        .onChange(of: appState.dailyTasks) { _, _ in
            appState.cancelSnoozeGuardIfNeeded()
        }
        .sheet(isPresented: $isShowingReportModal) {
            SleepReportModalView().presentationDetents([.medium, .large])
        }
    }
}

// ==========================================
// MARK: - ヘッダー部品 (HeaderView) ミニマルデザイン版
// ==========================================

struct HeaderView: View {
    let departureTime: String
    let travelTime: String
    let feelsLikeTemp: String
    let iconName: String
    let isWeatherIconSystem: Bool
    
    let travelMode: String
    let routeSummary: String

    let isDelay: Bool
    /// 背景が明るい（朝・日中の晴天など）か。glassと文字色をiOS天気アプリ風に出し分ける。
    let isBright: Bool

    // 移動手段に応じたアイコン
    var modeIcon: String {
        switch travelMode {
        case "driving": return "car"
        case "transit": return "tram.fill"
        case "walking": return "figure.walk"
        default:        return "car"
        }
    }
    
    var modeLabel: String {
        switch travelMode {
        case "driving": return "車"
        case "transit": return "電車"
        case "walking": return "徒歩"
        default:        return "移動"
        }
    }
    
    /// 遅延時のアクセント。赤枠でなく「オレンジのガラス」で上品に警告する。
    private var delayAccent: Color { Color(red: 1.0, green: 0.55, blue: 0.15) }

    // ★ カラフルな色分けを廃止し、統一感のあるモノトーンへ (遅延時のみオレンジ)
    var statusColor: Color {
        if isDelay { return delayAccent }
        return .primary
    }
    
    var body: some View {
        HStack {
            // --- 左側: 出発・移動情報 ---
            HStack(spacing: 12) {
                // アイコン
                Image(systemName: modeIcon)
                    .font(.title3)
                    .foregroundStyle(isDelay ? delayAccent : .primary.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(isDelay ? delayAccent.opacity(0.18) : Color.primary.opacity(0.08))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    // 出発時刻
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("出発")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(departureTime)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(isDelay ? delayAccent : .primary)
                    }

                    // 手段・状況・所要時間
                    Text("\(modeLabel) (\(routeSummary)) • \(travelTime)")
                        .font(.caption2)
                        .foregroundStyle(isDelay ? delayAccent.opacity(0.85) : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // 透過ガラス（空が透ける）。Materialへの .opacity は効かないので
            // シェイプにビュー修飾子の .opacity を掛けて確実に半透明化する。
            // 遅延時は赤枠でなく、ガラスにオレンジの色味を溶かした「オレンジガラス」にする。
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(delayAccent.opacity(isDelay ? 0.22 : 0))
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // 縁: 通常は淡い白、遅延時は柔らかいオレンジの縁
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isDelay ? delayAccent.opacity(0.55) : .primary.opacity(0.28),
                                  lineWidth: isDelay ? 1.0 : 0.6)
            )
            // 明るい空では濃色文字、暗い空では白文字に切替（ガラスは透過のまま）
            .environment(\.colorScheme, isBright ? .light : .dark)

            Spacer()
            
            // --- 右側: 天気情報 ---
            // --- 右側: 天気情報 ---
                        HStack(spacing: 8) {
                            // ★★★ 修正: フラグによって Image と Image(systemName:) を出し分ける ★★★
                            if isWeatherIconSystem {
                                Image(systemName: iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(.primary)
                            } else {
                                Image(iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                                    .opacity(0.9)
                            }

                            Text(feelsLikeTemp)
                                .font(.headline)
                        }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // 透過ガラス（空が透ける）。シェイプに .opacity を掛けて確実に半透明化。
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .opacity(0.6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.primary.opacity(0.28), lineWidth: 0.6)
            )
            // 明るい空では濃色文字、暗い空では白文字に切替（ガラスは透過のまま）
            .environment(\.colorScheme, isBright ? .light : .dark)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}
