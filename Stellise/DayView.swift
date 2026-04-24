import SwiftUI
import EventKit

struct DayView: View {

    @EnvironmentObject var appState: AppState
    @State private var isShowingReportModal: Bool = false
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    private var allTasksCompleted: Bool {
        !appState.dailyTasks.isEmpty && appState.dailyTasks.allSatisfy { $0.isCompleted }
    }
    private var dateString: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "M月d日 EEEE"
            return formatter.string(from: Date())
        }
    
    var body: some View {
            ZStack {
                // 背景画像
                Image(appState.backgroundImageName)
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity.animation(.easeOut(duration: 1.0)))
                
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
                            .background(Color.red.opacity(0.85))
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
                                                isDelay: appState.isTrafficDelayDetected
                                            )
                        
                        // --- 時計 (スマート・ミニマルスタイル) ---
                        VStack(spacing: 0) {
                            // 時間
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                Text(context.date, style: .time)
                                    .font(.system(size: 96, weight: .thin, design: .default))
                                    .monospacedDigit()
                                    // ★★★ 修正: 背景が明るい時は黒、暗い時は白 ★★★
                                    .foregroundStyle(appState.isBrightBackground ? .black : .white)
                                    // 見やすさを考慮し、以前の派手なシャドウは削除しました
                            }
                            
                            // 日付
                            Text(dateString)
                                .font(.system(.title3, design: .default, weight: .regular))
                                .tracking(3)
                                // ★★★ 修正: 背景が明るい時は黒、暗い時は白 ★★★
                                .foregroundStyle(appState.isBrightBackground ? .black.opacity(0.8) : Color.white.opacity(0.8))
                        }
                        .padding(.vertical, 36)
                        
                        // タスクリスト
                        if allTasksCompleted {
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
                            Spacer()
                            
                        } else {
                            List {
                                ForEach($appState.dailyTasks) { $task in
                                    if !task.isCompleted {
                                        // ★★★ 修正: TaskRowViewの呼び出しに source を追加 (UI判定用) ★★★
                                        TaskRowView(task: $task,  onFeedbackGood: { // ★ appStateを追加
                                            appState.recordFeedback(taskTitle: task.title, isGood: true)
                                        },
                                                    onFeedbackBad: {
                                            appState.recordFeedback(taskTitle: task.title, isGood: false)
                                        })
                                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                            .listRowSeparator(.hidden)
                                            .listRowBackground(Color.clear)
                                            .padding(.vertical, 6)
                                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                                Button {
                                                    // 完了時の触覚フィードバック
                                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                                    generator.impactOccurred()
                                                    
                                                    withAnimation {
                                                        task.isCompleted = true
                                                    }
                                                } label: {
                                                    Label("完了", systemImage: "checkmark")
                                                }
                                                .tint(Color.blue.opacity(0.7)) // 蛍光グリーンから落ち着いたブルーへ
                                            }
                                    }
                                }
                                
                                .onDelete { indexSet in
                                    appState.dailyTasks.remove(atOffsets: indexSet)
                                }
                                Section {
                                                                    Text("AIは間違えることがあります。重要な情報は確認してください。")
                                                                        .font(.caption2)
                                                                        .foregroundStyle(.secondary)
                                                                        .frame(maxWidth: .infinity, alignment: .center)
                                                                        .listRowBackground(Color.clear)
                                                                        .listRowSeparator(.hidden)
                                                                        .padding(.top, 10)
                                                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }
            }
            
            .onAppear {
            if appState.dailyTasks.isEmpty || appState.connectionError {
                Task {
                    await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium)
                }
            }
            if appState.lastSleepScore > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isShowingReportModal = true }
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
    
    // ★ カラフルな色分けを廃止し、統一感のあるモノトーンへ (遅延時のみ赤)
    var statusColor: Color {
        if isDelay { return .red }
        return .primary
    }
    
    var body: some View {
        HStack {
            // --- 左側: 出発・移動情報 ---
            HStack(spacing: 12) {
                // アイコン
                Image(systemName: modeIcon)
                    .font(.title3)
                    .foregroundStyle(isDelay ? .red : .primary.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(isDelay ? Color.red.opacity(0.15) : Color.primary.opacity(0.08))
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
                            .foregroundStyle(isDelay ? .red : .primary)
                    }
                    
                    // 手段・状況・所要時間
                    Text("\(modeLabel) (\(routeSummary)) • \(travelTime)")
                        .font(.caption2)
                        .foregroundStyle(isDelay ? .red.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            // 遅延時のみ細い赤い線を出す
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isDelay ? Color.red.opacity(0.4) : Color.clear, lineWidth: 0.5)
            )
            
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
                                    .foregroundStyle(.white)
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}
