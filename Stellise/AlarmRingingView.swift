//
//  AlarmRingingView.swift
//  Stellise
//
//  Created by yuu on 2025/11/06.
//


import SwiftUI
import Combine

struct AlarmRingingView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    @State private var flashOpacity: Double = 0.0
        // ★ 2. 元の画面の明るさを保存する State
    @State private var originalBrightness: CGFloat = 0.0
    // 夜→朝への色変化用（ゆっくり明るくなる「日の出」演出）
    @State private var dawnOpacity: Double = 0
    // 呼吸に同期した波紋（Headspace的な演出）
    @State private var rippleGrow: Bool = false
    @State private var breathTick = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()
    @Environment(\.scenePhase) private var scenePhase

    private var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    var body: some View {
        ZStack {

            // ★★★ 修正（ここから） ★★★

                        // --- レイヤー 1 (一番下) ---
                        // 背景: 夜の紺グラデ → 呼び出しが続くほどゆっくり明るい朝色へ
                        ZStack {
                            LinearGradient.nightImmersive
                            LinearGradient(
                                colors: [Color(hex: "#2A2A4E"), Color(hex: "#6E4A78"), Color(hex: "#E8A878")],
                                startPoint: .top, endPoint: .bottom
                            )
                            .opacity(dawnOpacity)
                        }
                        .edgesIgnoringSafeArea(.all)

                        // --- レイヤー 2 ---
                        // 呼吸に同期して広がる波紋（強い明滅の代わりに、心拍を上げない柔らかい演出）
                        ZStack {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .stroke(Theme.Palette.accentLight.opacity(0.45), lineWidth: 2)
                                    .scaleEffect(rippleGrow ? 2.4 : 0.3)
                                    .opacity(rippleGrow ? 0 : 0.6)
                                    // 停止時(false)に repeatForever が逆再生され続けないよう、開始時のみ適用する
                                    .animation(
                                        rippleGrow
                                            ? .easeOut(duration: 2.6)
                                                .repeatForever(autoreverses: false)
                                                .delay(Double(i) * 0.85)
                                            : nil,
                                        value: rippleGrow
                                    )
                            }
                        }
                        .frame(width: 260, height: 260)
                        .allowsHitTesting(false)

                        // 点滅する光 (VStackの後ろに移動)
                        RadialGradient(
                            gradient: Gradient(colors: [.clear, .clear, .white]),
                            center: .center,
                            startRadius: 150,
                            endRadius: 350
                        )
                        .opacity(flashOpacity * 0.4)
                        .edgesIgnoringSafeArea(.all)
                        .animation(
                            .easeInOut(duration: 1.3)
                            .repeatForever(autoreverses: true),
                            value: flashOpacity
                        )
                        // ★「シールド」を解除
                        .allowsHitTesting(false)

                        // --- レイヤー 3 (一番上) ---
                        VStack(spacing: 40) {
                            Spacer()

                            // 1. 現在時刻
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                Text(context.date, style: .time)
                                    .font(Theme.Typography.clock(96))
                                    .foregroundStyle(Theme.Palette.textOnDark)
                            }

                            Spacer()

                            // 2. 停止ボタン
                            Button(action: {
                                handleStopButton()
                            }) {
                                Text("アラーム停止")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.appAccent)
                                    .foregroundStyle(.white)
                                    .cornerRadius(20)
                            }
                            .buttonStyle(PressSpringButtonStyle())
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)

                        }
                        .foregroundStyle(.white)

                    }
        .onAppear {
            if let screen = activeScreen {
                self.originalBrightness = screen.brightness
                // (2) 画面の明るさを最大にする
                screen.brightness = 1.0
            }

                        // (3) フチの点滅アニメーションを開始
                        withAnimation {
                            flashOpacity = 1.0
                        }
                        // 波紋アニメーションと、夜→朝の色変化をスタート
                        withAnimation { rippleGrow = true }
                        withAnimation(.linear(duration: 90)) { dawnOpacity = 0.85 }
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            }
        .onDisappear{
            activeScreen?.brightness = self.originalBrightness
                    }
        .onReceive(breathTick) { _ in
            // 波紋が広がるタイミングに合わせて、心拍を上げない柔らかい触覚を刻む
            guard appState.isAlarmRinging else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
        }
        .onChange(of: appState.isAlarmRinging) {

            if !appState.isAlarmRinging {
                // (2) 点滅アニメーションを停止
                withAnimation(.easeOut(duration: 0.5)) {
                    flashOpacity = 0.0
                    rippleGrow = false
                    dawnOpacity = 0
                }
                // (3) 明るさを元に戻す
                activeScreen?.brightness = self.originalBrightness
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // 鳴動中にホームへ出る／バックグラウンドに回ると明るさが最大のまま残るため、
            // 非アクティブ化のタイミングで明示的に元の明るさへ戻す
            if newPhase == .background || newPhase == .inactive {
                activeScreen?.brightness = self.originalBrightness
            } else if newPhase == .active && appState.isAlarmRinging {
                // 復帰時、まだ鳴動中なら再び明るさを最大にする
                activeScreen?.brightness = 1.0
            }
        }
        }

        /// 「アラーム停止」ボタンが押されたときの処理
        private func handleStopButton() {
            withAnimation(.easeOut(duration: 0.5)) {
                flashOpacity = 0.0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            appState.stopAlarm(isPremium: subscriptionManager.isPremium)
        }
    }
    
    // プレビュー用
    struct AlarmRingingView_Previews: PreviewProvider {
        static var previews: some View {
            let previewState = AppState()
            previewState.isAlarmRinging = true

            return AlarmRingingView()
                .environmentObject(previewState)
                .environmentObject(SubscriptionManager())
        }
    }
