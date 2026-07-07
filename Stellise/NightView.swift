import SwiftUI
import Combine

struct NightView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @State private var isShowingTimePicker = false
    @State private var now = Date()
    @State private var selectedTimerDuration: TimeInterval? = nil
    @State private var isShowingPremium = false
    @State private var hasAppeared = false
    @State private var ringProgress: Double = 0
    /// 段階的覚醒: アラーム30分前から0→1へ上がり、夜空に朝焼けをゆっくり滲ませる
    @State private var preDawnProgress: Double = 0

    var body: some View {
        ZStack {
            // 背景は StelliseApp の共有 Background3DView（朝⇄夜で連続）。ここでは持たない。

            // 段階的覚醒(ウェイクアップライト): アラーム30分前から朝焼けの色を少しずつ滲ませ、
            // 鳴動時の AlarmRingingView の日の出演出へ自然につなぐ
            if preDawnProgress > 0 {
                LinearGradient(
                    colors: [Color(hex: "#262049"), Color(hex: "#6E4A78"), Color(hex: "#E8A878")],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(preDawnProgress * 0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.linear(duration: 1.0), value: preDawnProgress)
            }

            // --- コンテンツ ---
            VStack(spacing: 0) {

                Spacer().frame(height: 20)

                Spacer()

                // --- 中央: 就寝〜起床の残り時間を示す円形リング ---
                VStack(spacing: 16) {
                    Text(appState.userData.userName.isEmpty
                         ? "おやすみなさい"
                         : "おやすみなさい、\(appState.userData.userName)さん")
                        .font(.system(.title3, design: .default, weight: .thin))
                        .tracking(2)
                        // 就寝前は純白を避け、色温度の低い温白で目への刺激を抑える
                        .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.92))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 8)

                    sleepRing
                        .opacity(hasAppeared ? 1 : 0)
                        .scaleEffect(hasAppeared ? 1 : 0.9)

                    // アラーム時刻 (タップでピッカーを開く)
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred() // 押した時の軽い振動
                        isShowingTimePicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.fill")
                                .font(.subheadline)
                            Text(String(format: "%02d:%02d 起床", appState.userData.alarmHour, appState.userData.alarmMinute))
                                .font(.system(.title3, design: .default, weight: .medium))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(Theme.Palette.nightWarmText)
                    .padding(.top, 4)
                    .opacity(hasAppeared ? 1 : 0)
                }

                Spacer()

                // --- 下部: 睡眠環境音セクション ---
                sleepSoundSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 16)
            } // VStackここまで
        } // ZStackここまで
        .onAppear {
            now = Date()
            appState.isAlarmFinished = false
            startSleepMonitoring()
            appState.requestNotificationPermission() // AlarmKit 権限ポップアップ（未許可時のみ表示）
            appState.scheduleMorningAlarm()
            UIApplication.shared.isIdleTimerDisabled = true
            withAnimation(.easeOut(duration: 1.4)) {
                hasAppeared = true
            }
        }
        .onDisappear {
            appState.sleepSoundManager.stopSound()
            
            // ★★★ 追加: 画面を離れる時はオートロックを元の設定(有効)に戻す ★★★
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $isShowingTimePicker, onDismiss: {
            // 「完了」を押さずスワイプで閉じても、変更済みの時刻を保存してOSに再予約する
            appState.save()
            appState.scheduleMorningAlarm()
        }) {
            // 時刻ピッカー (維持)
            VStack(spacing: 20) {
                Text("アラーム設定").font(.headline).padding(.top)
                DatePicker("", selection: Binding(
                    get: {
                        let calendar = Calendar.current
                        let components = DateComponents(hour: appState.userData.alarmHour, minute: appState.userData.alarmMinute)
                        return calendar.date(from: components) ?? Date()
                    },
                    set: { newDate in
                        let comp = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                        appState.userData.alarmHour = comp.hour ?? appState.userData.alarmHour
                        appState.userData.alarmMinute = comp.minute ?? appState.userData.alarmMinute
                    }
                ), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).labelsHidden()
                Button("完了") {
                    isShowingTimePicker = false
                    appState.save()

                    // ★★★ 追加: ピッカーを閉じたら、OSに新しい時間を予約する ★★★
                    appState.requestNotificationPermission() // 初回のみ許可ダイアログが出る
                    appState.scheduleMorningAlarm()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }.padding()
                
            }
            .presentationDetents([.medium])
        }
        // ※アラーム画面の表示は StelliseApp 側 (zIndex 999 のオーバーレイ) に一本化。
        //   ここでも fullScreenCover を出すと二重表示になり、画面輝度の保存/復元が壊れる。
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { nowTime in
            // タイマー監視・スマートアラーム判定ロジック (維持)
            self.now = nowTime

            let calendar = Calendar.current
            var comp = calendar.dateComponents([.year, .month, .day], from: nowTime)
            comp.hour = appState.userData.alarmHour
            comp.minute = appState.userData.alarmMinute
            guard let alarmDate = calendar.date(from: comp) else { return }

            let targetDate = alarmDate < nowTime.addingTimeInterval(-60) ? alarmDate.addingTimeInterval(86400) : alarmDate
            let timeUntilAlarm = targetDate.timeIntervalSince(nowTime)
            ringProgress = sleepProgress(now: nowTime, wake: targetDate)
            // アラーム30分前から朝焼けを滲ませる（アラームOFF時は出さない）
            preDawnProgress = appState.userData.isAlarmActive
                ? min(1, max(0, 1 - timeUntilAlarm / 1800))
                : 0

            // スマートアラーム窓判定 (30分前からマイクON)
            if timeUntilAlarm <= 1800 && timeUntilAlarm > 0 {
                appState.isSmartAlarmWindow = true
            } else {
                appState.isSmartAlarmWindow = false
            }
            
            // 通常アラーム発動判定
            if appState.userData.isAlarmActive && !appState.isAlarmRinging && !isShowingTimePicker && !appState.isAlarmFinished {
                if timeUntilAlarm <= 0 && timeUntilAlarm > -60 {
                    print("⏰ 時間到達: アラーム発動！")
                    // アラーム発火を起点に、朝のタスクを生成（朝画面の自動生成は廃止したため）
                    Task { await appState.refreshSmartSchedule(isPremium: subscriptionManager.isPremium) }
                    appState.isAlarmRinging = true
                    appState.startAlarmEffects()
                }
            }
        }
    } // body

    // ==========================================
    // MARK: - 就寝〜起床リング
    // ==========================================

    /// 就寝〜起床の残り時間を示す円形リング。中央に「あと◯時間◯分」＋起床時刻。
    private var sleepRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 14)

            Circle()
                .trim(from: 0, to: max(0.0035, ringProgress))
                .stroke(
                    AngularGradient(colors: [Theme.Palette.accentDeep, Theme.Palette.accent, Theme.Palette.accentLight],
                                     center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.Palette.accent.opacity(0.5), radius: 8)
                .animation(.easeInOut(duration: 0.6), value: ringProgress)

            VStack(spacing: 4) {
                Text("あと")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.65))
                Text(remainingUntilAlarmText)
                    .font(Theme.Typography.clock(52))
                    .foregroundStyle(Theme.Palette.nightWarmText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(24)
        }
        .frame(width: 240, height: 240)
        .contentShape(Circle())
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            isShowingTimePicker = true
        }
    }

    /// 就寝(セッション開始)〜起床(アラーム時刻)を 0...1 で表す進捗。
    private func sleepProgress(now: Date, wake: Date) -> Double {
        let start = appState.sleepSessionStart ?? now
        let total = wake.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        return min(1, max(0, elapsed / total))
    }

    private var remainingUntilAlarmText: String {
        let calendar = Calendar.current
        var comp = calendar.dateComponents([.year, .month, .day], from: now)
        comp.hour = appState.userData.alarmHour
        comp.minute = appState.userData.alarmMinute
        guard let alarmDate = calendar.date(from: comp) else { return "--:--" }
        let targetDate = alarmDate < now.addingTimeInterval(-60) ? alarmDate.addingTimeInterval(86400) : alarmDate

        let remaining = max(0, targetDate.timeIntervalSince(now))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }

    // ==========================================
    // MARK: - 睡眠環境音セクション
    // ==========================================

    @ViewBuilder
    private var sleepSoundSection: some View {
        if subscriptionManager.isPremium {
            // Pro ユーザー: フル機能
            VStack(alignment: .leading, spacing: 12) {
                soundSectionHeader

                HStack(spacing: 12) {
                    // 再生 / 一時停止
                    Button {
                        appState.sleepSoundManager.togglePlay(timerDuration: selectedTimerDuration)
                    } label: {
                        Image(systemName: appState.sleepSoundManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }

                    // 音の種類
                    Menu {
                        ForEach(SleepSoundManager.SleepSound.allCases) { sound in
                            Button(sound.rawValue) {
                                appState.sleepSoundManager.selectedSound = sound
                                if appState.sleepSoundManager.isPlaying {
                                    appState.sleepSoundManager.playSound(timerDuration: selectedTimerDuration)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(appState.sleepSoundManager.selectedSound.rawValue)
                                .font(.caption)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(12)
                    }

                    Spacer(minLength: 0)

                    // タイマー残り表示
                    if let remaining = appState.sleepSoundManager.remainingTime {
                        Text(formatRemaining(remaining))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    // スリープタイマー
                    Menu {
                        Button("オフ") { selectedTimerDuration = nil }
                        Button("15分") { selectedTimerDuration = 15 * 60 }
                        Button("30分") { selectedTimerDuration = 30 * 60 }
                        Button("1時間") { selectedTimerDuration = 60 * 60 }
                    } label: {
                        Image(systemName: "timer")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(selectedTimerDuration == nil ? 0.3 : 0.7))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(24)
        } else {
            // 非 Pro ユーザー: ロックオーバーレイ
            ZStack {
                // コンテンツ（薄く表示）
                VStack(alignment: .leading, spacing: 12) {
                    soundSectionHeader

                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 36, height: 36)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 80, height: 32)
                        Spacer()
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(20)
                .opacity(0.35)
                .blur(radius: 2)

                // ロックオーバーレイ
                Button {
                    isShowingPremium = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                        Text("睡眠環境音は Pro 限定")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("タップしてアップグレード")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial)
            .cornerRadius(24)
            .sheet(isPresented: $isShowingPremium) {
                PremiumIntroView()
                    .environmentObject(subscriptionManager)
                    .environmentObject(appState)
            }
        }
    }

    private var soundSectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.subheadline)
                .foregroundStyle(.gray)
            Text("睡眠環境音")
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func formatRemaining(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    // ==========================================
    // MARK: - 内部ロジック
    // ==========================================
    private func startSleepMonitoring() {
        if !appState.sensorManager.isDetecting {
            print("🌙 NightView: 睡眠・音声センサー起動")
            appState.startNightSession() // 睡眠レポート用の集計を開始
            appState.sensorManager.startDetection(threshold: appState.movementThreshold)
            Task { await appState.soundAnalyzer.startAnalyzing() }
            appState.smartAlarmTriggered = false
        }
    }
}
