import SwiftUI

struct WelcomeView: View {
    
    // ★★★ 1. @State private var userName... を削除 ★★★
    
    // ★★★ 2. @EnvironmentObject を追加 ★★★
    // アプリの大元(SleepAppApp)から渡された「脳」を受け取る
    @EnvironmentObject var appState: AppState
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("ステップ 1 / 5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top)

                Spacer()
                Text("ようこそ！")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 12)

                Text("あなたの情報を教えてください！")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 12)

                // ★★★ 3. $userName を $appState.userData.userName に変更 ★★★
                TextField("名前を入力", text: $appState.userData.userName)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                    .padding(.top, 40)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 12)

                NavigationLink {
                    BedFirmnessView()
                } label: {
                    Text("次へ")
                        .fontWeight(.semibold)
                        .frame(width: 200, height: 50)
                        .background(isNameValid ? Color.appAccent : Color(.systemGray4))
                        .foregroundStyle(Color.white)
                        .cornerRadius(10)
                }
                .buttonStyle(PressSpringButtonStyle())
                .simultaneousGesture(TapGesture().onEnded {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                })
                .disabled(!isNameValid)
                .padding(.top, 20)
                .opacity(hasAppeared ? 1 : 0)
                Spacer()
            }
            .padding()
        }
        // ※初回画面での通知権限リクエストは廃止。
        //   アラーム権限(AlarmKit)は夜画面・アラーム設定時に文脈付きで要求される。
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
                hasAppeared = true
            }
        }
    }

    /// 空欄のまま進むと夜画面が「おやすみなさい、さん」になるのを防ぐ
    private var isNameValid: Bool {
        !appState.userData.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    
}

// プレビュー用 (プレビュー時だけダミーのAppStateを渡す)
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(AppState()) // ★★★ 4. この行を追加 ★★★
    }
}
