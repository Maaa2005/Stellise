import SwiftUI

struct BodyInfoView: View {
    
    // ★★★ 1. @State private var height/weight... を削除 ★★★
    
    // ★★★ 2. @EnvironmentObject を追加 ★★★
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Text("ステップ 2 / 5")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top)
        
        VStack(spacing: 16) {
            Spacer()
            Text("あなたのことを\n少し教えてください")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text("この情報は、推奨事項を改善するのに役立ちます。常に非公開にされます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // ★★★ 3. $height を $appState.userData.userHeight に変更 ★★★
            TextField("身長 (任意)", text: $appState.userData.userHeight)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 300)
                .padding(.top, 40)
            
            // ★★★ 4. $weight を $appState.userData.userWeight に変更 ★★★
            TextField("体重 (任意)", text: $appState.userData.userWeight)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .frame(width: 300)
            
            // ★★★ "Button" を "NavigationLink" に変更 ★★★
            NavigationLink {
                            // 遷移先のView
                            BedFirmnessView()
                        } label: {
                            // ボタンの見た目（中身は変更なし）
                            Text("次へ")
                                .fontWeight(.semibold)
                                .frame(width: 300, height: 50)
                                .background(Color.blue)
                                .foregroundStyle(Color.white)
                                .cornerRadius(10)
                        }
                        .padding(.top, 20)
                        // ★★★ "NavigationLink" が押された瞬間に保存処理を実行 ★★★
                        .simultaneousGesture(TapGesture().onEnded {
                            appState.save()
                            print("身長・体重を保存しました。")
                        })
            
            Spacer()
            Spacer()
        }
        .padding()
        .navigationTitle("あなたの情報")
    }
}

// プレビュー用
struct BodyInfoView_Previews: PreviewProvider {
    static var previews: some View {
        BodyInfoView()
            .environmentObject(AppState()) // ★★★ 6. この行を追加 ★★★
    }
}
