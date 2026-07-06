import SwiftUI

struct WelcomeView: View {
    
    // ★★★ 1. @State private var userName... を削除 ★★★
    
    // ★★★ 2. @EnvironmentObject を追加 ★★★
    // アプリの大元(SleepAppApp)から渡された「脳」を受け取る
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("ようこそ！")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("あなたの情報を教えてください！")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // ★★★ 3. $userName を $appState.userData.userName に変更 ★★★
                TextField("名前を入力", text: $appState.userData.userName)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 300)
                    .padding(.top, 40)

                NavigationLink {
                    BodyInfoView()
                } label: {
                    Text("次へ")
                        .fontWeight(.semibold)
                        .frame(width: 200, height: 50)
                        .background(isNameValid ? Color.appAccent : Color(.systemGray4))
                        .foregroundStyle(Color.white)
                        .cornerRadius(10)
                }
                .disabled(!isNameValid)
                .padding(.top, 20)
                Spacer()
            }
            .padding()
        }
        // ※初回画面での通知権限リクエストは廃止。
        //   アラーム権限(AlarmKit)は夜画面・アラーム設定時に文脈付きで要求される。
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
