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

    /// 中央の就寝情報を、背景上部の表示と重ならない位置まで下げる。
    private let sleepStatusVerticalOffset: CGFloat = 48

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

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.32)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // --- コンテンツ ---
            VStack(spacing: 0) {

                Spacer().frame(height: 20)

                Spacer()

                // --- 中央: 就寝〜起床の残り時間を示す円形リング ---
                // リングは内側の星フィールド(300pt)とグロー(1.08倍)が240ptの枠外へ約30pt
                // はみ出す。起床チップがそこに重ならないよう十分な間隔を空ける。
                VStack(spacing: 44) {
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
                        .frame(minHeight: 48)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Theme.Palette.nightWarmText.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .foregroundStyle(Theme.Palette.nightWarmText)
                    .padding(.top, 4)
                    .opacity(hasAppeared ? 1 : 0)
                    .buttonStyle(PressSpringButtonStyle())
                }
                .offset(y: sleepStatusVerticalOffset)

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

            // スマートアラーム窓判定 (30分前から)。設定OFF・アラームOFFのときは開かない
            if timeUntilAlarm <= 1800 && timeUntilAlarm > 0
                && appState.userData.isSmartAlarmEnabled
                && appState.userData.isAlarmActive {
                appState.isSmartAlarmWindow = true
            } else {
                appState.isSmartAlarmWindow = false
            }
            
            // 通常アラーム発動判定
            if appState.userData.isAlarmActive && !appState.isAlarmRinging && !isShowingTimePicker && !appState.isAlarmFinished {
                if timeUntilAlarm <= 0 && timeUntilAlarm > -60 {
                    debugLog("⏰ 時間到達: アラーム発動！")
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
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.Palette.nightWarmText.opacity(0.10),
                            Theme.Palette.accentDeep.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 18,
                        endRadius: 150
                    )
                )
                .blur(radius: 24)
                .scaleEffect(1.08)

            // 眠りの進行(ringProgress)に応じてリングの外側に星が増えていく演出（控えめ・静的）
            starField
                .allowsHitTesting(false)

            Circle()
                .stroke(Theme.Palette.nightWarmText.opacity(0.12), lineWidth: 14)

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

    /// リング進捗(ringProgress)が進むほど星が増えていく背景演出。
    /// 星は決定論的に配置（シード固定の擬似乱数）した静的な点で、TimelineViewは使わない。
    /// ringProgressが毎秒更新されるたびに表示数(Int(ringProgress * 24))が増えるだけで自然に増殖して見える。
    private var starField: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let visibleCount = Int(ringProgress * Double(Self.nightStars.count))
            for star in Self.nightStars.prefix(visibleCount) {
                let point = CGPoint(
                    x: center.x + CGFloat(cos(star.angle) * star.radius),
                    y: center.y + CGFloat(sin(star.angle) * star.radius)
                )
                let rect = CGRect(x: point.x - star.diameter / 2, y: point.y - star.diameter / 2,
                                   width: star.diameter, height: star.diameter)
                context.opacity = star.opacity
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .frame(width: 300, height: 300)
    }

    /// 星1つ分の決定論的な配置情報。
    private struct NightStar {
        let angle: Double     // ラジアン
        let radius: Double    // 中心からの距離(pt)
        let diameter: Double  // 直径(pt)。半径0.8〜1.6pt相当
        let opacity: Double
    }

    /// 星フィールドの固定配置（シード付き擬似乱数で決定論的に生成）。
    /// sleepRing(240x240・半径120・線幅14＝おおよそ半径113〜127がリング線)を避けるため、
    /// 半径130〜150ptの範囲（リング外側〜Canvas 300x300の縁付近）にのみ配置する。
    private static let nightStars: [NightStar] = {
        var seed: UInt64 = 20260707
        func nextUnit() -> Double {
            // 決定論的な疑似乱数(LCG)。毎回同じ配置になる。
            seed = 6364136223846793005 &* seed &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        var stars: [NightStar] = []
        for _ in 0..<24 {
            let angle = nextUnit() * 2 * .pi
            let radius = 130 + nextUnit() * 20        // 130...150pt（リング線上を避ける）
            let diameter = 1.6 + nextUnit() * 1.6      // 直径1.6〜3.2pt（半径0.8〜1.6pt）
            let opacity = 0.4 + nextUnit() * 0.4       // 0.4〜0.8
            stars.append(NightStar(angle: angle, radius: radius, diameter: diameter, opacity: opacity))
        }
        return stars
    }()

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
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .background(Theme.Palette.nightWarmText.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PressSpringButtonStyle())

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
                        .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.88))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.Palette.nightWarmText.opacity(0.08), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    // タイマー残り表示
                    if let remaining = appState.sleepSoundManager.remainingTime {
                        Text(formatRemaining(remaining))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.62))
                    }

                    // スリープタイマー
                    Menu {
                        Button("オフ") { selectedTimerDuration = nil }
                        Button("15分") { selectedTimerDuration = 15 * 60 }
                        Button("30分") { selectedTimerDuration = 30 * 60 }
                        Button("1時間") { selectedTimerDuration = 60 * 60 }
                    } label: {
                        Image(systemName: "timer")
                            .font(.headline)
                            .foregroundStyle(Theme.Palette.nightWarmText.opacity(selectedTimerDuration == nil ? 0.34 : 0.78))
                            .frame(width: 44, height: 44)
                            .background(Theme.Palette.nightWarmText.opacity(selectedTimerDuration == nil ? 0.06 : 0.10))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(20)
            .nightSleepPanel()
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
                            .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.92))
                        Text("睡眠環境音は Pro 限定")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.9))
                        Text("タップしてアップグレード")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.plain)
            }
            .nightSleepPanel()
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
                .foregroundStyle(Theme.Palette.accentLight.opacity(0.78))
            Text("睡眠環境音")
                .font(.system(.callout, design: .default, weight: .medium))
                .foregroundStyle(Theme.Palette.nightWarmText.opacity(0.82))
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
            debugLog("🌙 NightView: 睡眠・音声センサー起動")
            appState.startNightSession() // 睡眠レポート用の集計を開始
            appState.sensorManager.startDetection(threshold: appState.movementThreshold)
            Task { await appState.soundAnalyzer.startAnalyzing() }
            appState.smartAlarmTriggered = false
        }
    }
}
