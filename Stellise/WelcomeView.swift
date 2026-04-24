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
                        .background(Color.blue)
                        .foregroundStyle(Color.white)
                        .cornerRadius(10)
                }
                .padding(.top, 20)
                Spacer()
            }
            .padding()
        }
        // WelcomeView.swift の「次へ」ボタンなどのアクション内、
        // または .onAppear に追加
        .onAppear {
            // 起動時に通知の許可を求める
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                if granted {
                    print("✅ 通知許可OK")
                }
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
