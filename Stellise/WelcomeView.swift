import SwiftUI

struct WelcomeView: View {
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ZStack {
                OnboardingBackground()

                VStack(spacing: 0) {
                    OnboardingProgressHeader(step: 1, total: 5)

                    ScrollView {
                        VStack(spacing: 28) {
                            OnboardingHero(
                                symbol: "sparkles",
                                title: "Stelliseへようこそ",
                                description: "あなたの朝に合わせた起床体験をつくるため、\n睡眠環境と朝のルーティンを設定します。"
                            )
                            .padding(.top, 72)

                            NavigationLink {
                                BedFirmnessView()
                            } label: {
                                OnboardingPrimaryLabel(title: "設定を始める")
                            }
                            .buttonStyle(PressSpringButtonStyle())
                            .simultaneousGesture(TapGesture().onEnded {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            })
                            .padding(.top, 24)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 12)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .toolbar(.hidden, for: .navigationBar)
        }
        // ※初回画面での通知権限リクエストは廃止。
        //   アラーム権限(AlarmKit)は夜画面・アラーム設定時に文脈付きで要求される。
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                hasAppeared = true
            }
        }
    }

}

// プレビュー用 (プレビュー時だけダミーのAppStateを渡す)
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(AppState()) // ★★★ 4. この行を追加 ★★★
    }
}
