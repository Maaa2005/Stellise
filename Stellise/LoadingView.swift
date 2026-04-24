import SwiftUI

struct LoadingView: View {
    
    // ★ 1. あなたがAssetに追加した「紺色の背景」の名前に書き換えてください
    private let mainBackgroundImage = "loading_main" // (AppBankgroundColor.jpg)
    
    // ★ 2. あなたがAssetに追加した「猫の画像」のリストに書き換えてください
    private let randomCatImages: [String] = [
        "cat_loading_1", // 例: ...172217.jpg
        "cat_loading_2", // 例: ...172236.jpg
        "cat_loading_3", // 例: ...172253.jpg
        "cat_loading_4", // (4枚目)
        "cat_loading_5"  // (5枚目)
    ]
    
    @State private var selectedCatImage: String? = nil
    @State private var showContent = false // フワッと表示させるためのState

    var body: some View {
        ZStack {
            
            // --- レイヤー 1 (一番下) ---
            // 起動の「隙間」を埋めるための、PNGとそっくりな「紺色」
            Color("AppBackgroundColor")
                .edgesIgnoringSafeArea(.all)
            
            // --- レイヤー 2 ---
            // あなたの「紺色のPNG」背景
            Image(mainBackgroundImage)
                .resizable()
                .scaledToFill()
                .edgesIgnoringSafeArea(.all)
                .opacity(showContent ? 1 : 0) // フワッと表示

            // --- レイヤー 3 ---
            // ランダムに選ばれた「猫の画像」
            if let catImage = selectedCatImage {
                Image(catImage)
                    .resizable()
                    .scaledToFit() // アスペクト比を維持して中央に
                    .padding(60) // 画面の端から少し離す
                    .opacity(showContent ? 1 : 0) // フワッと表示
            }
            
            // --- レイヤー 4 (一番上) ---
            // おしゃれな「グルグル」
            VStack {
                Spacer() // グルグルを画面下部に配置
                
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white.opacity(0.8)) // 半透明の白
                    .scaleEffect(1.5) // 少し大きく
                    .padding(.bottom, 120) // タブバーの上あたり
            }
            .opacity(showContent ? 1 : 0) // フワッと表示
            
        }
        .onAppear {
            // このViewが表示されたら、ランダムに猫を1枚選ぶ
            if selectedCatImage == nil {
                selectedCatImage = randomCatImages.randomElement()
            }
            
            // 0.1秒後に、すべてのレイヤーをフワッと表示させる
            // (0.1秒待つことで、背景色の切り替わりを確実にごまかす)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 0.75)) {
                    showContent = true
                }
            }
        }
    }
}

// プレビュー用
struct LoadingView_Previews: PreviewProvider {
    static var previews: some View {
        LoadingView()
    }
}
