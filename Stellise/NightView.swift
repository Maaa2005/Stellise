import SwiftUI
import Combine

struct NightView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @State private var isShowingTimePicker = false
    @State private var now = Date()
    @State private var selectedTimerDuration: TimeInterval? = nil // スリープタイマー (オフ)
    
    var body: some View {
        ZStack {
            // 背景画像 (夜)
            Image("image-space-background") // 既存のアセット画像名
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
                .transition(.opacity.animation(.easeOut(duration: 1.0)))
            
            // --- コンテンツ ---
            VStack(spacing: 0) {
                
                // ★★★ 修正: 日付と天気があったHeader部分を削除し、上部の余白だけを確保 ★★★
                Spacer().frame(height: 20)
                
                Spacer()
                
                // --- 中央: 時間表示 (現在時刻メイン) --- (維持)
                VStack(spacing: 12) {
                    Text("おやすみなさい、\(appState.userData.userName)さん")
                        .font(.system(.title3, design: .default, weight: .thin))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                    
                    // 現在時刻
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        Text(context.date, style: .time)
                            .font(.system(size: 100, weight: .thin, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: Color.white.opacity(0.2), radius: 10, x: 0, y: 0)
                    }
                    
                    // アラーム時刻 (タップでピッカーを開く)
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred() // 押した時の軽い振動
                        isShowingTimePicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.fill")
                                .font(.subheadline)
                            Text(String(format: "%02d:%02d", appState.userData.alarmHour, appState.userData.alarmMinute))
                                .font(.system(.title2, design: .default, weight: .regular))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // --- 下部: 睡眠環境音セクション ---
                // ★★★ 修正: ミッションセクションを削除し、睡眠音セクションのみを中央寄せにする ★★★
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("睡眠環境音")
                            .font(.system(.callout, design: .default, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    
                    HStack(spacing: 12) {
                        // 再生/停止
                        Button(action: {
                            appState.sleepSoundManager.togglePlay(premium: subscriptionManager.isPremium, timerDuration: selectedTimerDuration)
                        }) {
                            Image(systemName: appState.sleepSoundManager.isPlaying ? "stop.fill" : "play.fill")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.6))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        // 音の種類
                        Menu {
                            ForEach(SleepSoundManager.SleepSound.allCases) { sound in
                                Button(sound.rawValue) {
                                    appState.sleepSoundManager.selectedSound = sound
                                    if appState.sleepSoundManager.isPlaying {
                                        appState.sleepSoundManager.playSound(premium: subscriptionManager.isPremium, timerDuration: selectedTimerDuration)
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
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        Spacer(minLength: 0)
                        
                        // タイマー
                        Menu {
                            Button("オフ", action: { selectedTimerDuration = nil })
                            Button("15分", action: { selectedTimerDuration = 15 * 60 })
                            Button("30分", action: { selectedTimerDuration = 30 * 60 })
                            Button("1時間", action: { selectedTimerDuration = 60 * 60 })
                        } label: {
                            Image(systemName: "timer")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(selectedTimerDuration == nil ? 0.3 : 0.6))
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal, 24) // セクション全体の左右余白
                .padding(.bottom, 24)     // 下部の余白
            } // VStackここまで
            
            // ★★★ 追加: うつ伏せブラックアウト機能 (省電力対応) ★★★
            // 有機ELディスプレイ(OLED)は、真っ黒な画面を被せるだけで劇的なバッテリー節約になります。
          
        } // ZStackここまで
        .onAppear {
            now = Date()
            appState.isAlarmFinished = false
            startSleepMonitoring()
            appState.scheduleMorningAlarm()
            
            // ★★★ 追加: 画面のオートロック(自動スリープ)を無効化 ★★★
            // アラームアプリとして、途中で画面が勝手に消えるのを防ぎます。
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            appState.sleepSoundManager.stopSound()
            
            // ★★★ 追加: 画面を離れる時はオートロックを元の設定(有効)に戻す ★★★
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $isShowingTimePicker) {
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
                Button("完了") { isShowingTimePicker = false
                                        appState.save()
                                        
                                        // ★★★ 追加: ピッカーを閉じたら、OSに新しい時間を予約する ★★★
                                        appState.requestNotificationPermission() // 初回のみ許可ダイアログが出る
                                        appState.scheduleMorningAlarm()}.padding()
                
            }
            .presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $appState.isAlarmRinging) {
            AlarmRingingView() // アラーム画面 (維持)
        }
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
                    appState.generateNewMission()
                    appState.isAlarmRinging = true
                    appState.startAlarmEffects()
                }
            }
        }
    } // body
    
    // ==========================================
    // MARK: - 内部ロジック
    // ==========================================
    private func startSleepMonitoring() {
        if !appState.sensorManager.isDetecting {
            print("🌙 NightView: 睡眠・音声センサー起動")
            appState.sensorManager.startDetection(threshold: appState.movementThreshold)
            Task { await appState.soundAnalyzer.startAnalyzing() }
            appState.smartAlarmTriggered = false
        }
    }
}
