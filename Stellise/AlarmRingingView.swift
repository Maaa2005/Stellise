//
//  AlarmRingingView.swift
//  Stellise
//
//  Created by yuu on 2025/11/06.
//


import SwiftUI

struct AlarmRingingView: View {
    
    @EnvironmentObject var appState: AppState
    
    // 答えが間違っていた時にViewを揺らすためのState
    @State private var shakeOffset: CGFloat = 0
    @FocusState private var isTextFieldFocused: Bool
    @State private var flashOpacity: Double = 0.0
        // ★ 2. 元の画面の明るさを保存する State
    @State private var originalBrightness: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            
            // ★★★ 修正（ここから） ★★★
                        
                        // --- レイヤー 1 (一番下) ---
                        // 背景 (暗めの色)
                        Color.black.opacity(0.8)
                            .edgesIgnoringSafeArea(.all)

                        // --- レイヤー 2 ---
                        // 点滅する光 (VStackの後ろに移動)
                        RadialGradient(
                            gradient: Gradient(colors: [.clear, .clear, .white]),
                            center: .center,
                            startRadius: 150,
                            endRadius: 350
                        )
                        .opacity(flashOpacity)
                        .edgesIgnoringSafeArea(.all)
                        .animation(
                            .easeInOut(duration: 0.2)
                            .repeatForever(autoreverses: true),
                            value: flashOpacity
                        )
                        // ★「シールド」を解除
                        .allowsHitTesting(false)

                        // --- レイヤー 3 (一番上) ---
                        // ボタンや計算問題 (これが一番手前に来る)
                        VStack(spacing: 40) {
                            Spacer()
                            
                            // 1. 現在時刻
                            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                                Text(context.date, style: .time)
                                    .font(.system(size: 96, weight: .thin))
                                    .monospacedDigit()
                            }
                            
                            // 2. ミッション
                            VStack(spacing: 20) {
                                Text("ミッション: 計算を解いてください")
                                    .font(.title3)
                                
                                Text("\(appState.missionNumber1) + \(appState.missionNumber2) = ?")
                                    .font(.system(size: 48, weight: .bold))
                                    .monospacedDigit()
                                
                                // ★ 私が前回削除してしまった .focused を「復活」させます
                                TextField("答え", text: $appState.missionAnswerText)
                                    .font(.system(size: 40, weight: .bold))
                                    .keyboardType(.numberPad) // 数字キーボード
                                    .multilineTextAlignment(.center)
                                    .padding()
                                    .background(.white.opacity(0.1))
                                    .cornerRadius(10)
                                    .frame(maxWidth: 200)
                                    .focused($isTextFieldFocused) // ★ これを復活
                            }
                            
                            Spacer()
                            
                            // 3. 停止ボタン
                            Button(action: {
                                handleStopButton()
                            }) {
                                Text("アラーム停止")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.blue)
                                    .foregroundStyle(.white)
                                    .cornerRadius(20)
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 20)
                            
                        }
                        .foregroundStyle(.white)
                        // Viewを揺らすためのオフセット
                        .offset(x: shakeOffset)
                        
                        // ★ (RadialGradient は レイヤー2 に移動済み)
                        
                        // ★★★ 修正（ここまで） ★★★
                        
                    }
                    // 画面が表示された瞬間にキーボードを自動で表示
        // 画面が表示された瞬間にキーボードを自動で表示
        .onAppear {
            self.originalBrightness = UIScreen.main.brightness
                        // (2) 画面の明るさを最大にする
                        UIScreen.main.brightness = 1.0
                        
                        // (3) フチの点滅アニメーションを開始
                        withAnimation {
                            flashOpacity = 1.0
                        }
            
                // 少し待たないとキーボードが表示されないことがある
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTextFieldFocused = true
                    // SwiftUIでTextFieldにフォーカスを当てるのは少し工夫が必要ですが、
                    // まずはロジックの動作確認を優先します。
                    // (もしうまく動かなければ、iOS 15以降の @FocusState を使います)
                }
            }
        .onDisappear{
            UIScreen.main.brightness = self.originalBrightness
                    }
        .onChange(of: appState.isAlarmRinging) {
            
            if !appState.isAlarmRinging {
                // (2) 点滅アニメーションを停止
                withAnimation(.easeOut(duration: 0.5)) {
                    flashOpacity = 0.0
                }
                // (3) 明るさを元に戻す
                UIScreen.main.brightness = self.originalBrightness
            }
        }
        }
        
        /// 「アラーム停止」ボタンが押されたときの処理
        private func handleStopButton() {
            if appState.checkMissionAnswer() {
                // 答えが正しい
                isTextFieldFocused = false
                withAnimation(.easeOut(duration: 0.5)) {
                                flashOpacity = 0.0
                            }
                appState.stopAlarm()
            } else {
                // 答えが間違い
                triggerShakeAnimation()
                appState.missionAnswerText = "" // 入力欄をクリア
                isTextFieldFocused = false
                DispatchQueue.main.async {
                    isTextFieldFocused = true
                }
            }
        }
        
        /// 答えが間違った時にViewを揺らすアニメーション
        private func triggerShakeAnimation() {
            withAnimation(.linear(duration: 0.05).repeatCount(5)) {
                shakeOffset = -10
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.linear(duration: 0.05)) {
                    shakeOffset = 0
                }
            }
        }
    }
    
    // プレビュー用
    struct AlarmRingingView_Previews: PreviewProvider {
        static var previews: some View {
            let previewState = AppState()
            previewState.isAlarmRinging = true
            previewState.missionNumber1 = 15
            previewState.missionNumber2 = 7
            
            return AlarmRingingView()
                .environmentObject(previewState)
        }
    }

