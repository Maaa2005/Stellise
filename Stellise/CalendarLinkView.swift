import SwiftUI
import SafariServices // ★ブラウザを表示するために追加

struct CalendarLinkView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var isAgreed = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingTerms = false
    
    var body: some View {
        VStack {
            Text("ステップ 5 / 5")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top)
            
            Spacer()
            
            VStack(spacing: 24) {
                // アイコン部分
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .padding(.bottom, 10)
                
                Text("カレンダーを連携しますか？")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("イベントをタスクとして自動的にインポートし、時間を節約して整理整頓しましょう。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // --- 利用規約・プライバシーポリシー同意セクション ---
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Button(action: { isAgreed.toggle() }) {
                            Image(systemName: isAgreed ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isAgreed ? .blue : .gray)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 0) {
                                Button("利用規約") { isShowingTerms = true }
                                    .foregroundStyle(.blue)
                                Text(" と ")
                                Button("プライバシーポリシー") { isShowingPrivacyPolicy = true }
                                    .foregroundStyle(.blue)
                                Text(" に")
                            }
                            Text("同意して、Stelliseの利用を開始します。")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 300)
                }
                .padding(.vertical, 20)
                
                // --- 連携ボタン ---
                // --- 連携ボタン ---
                                NavigationLink(destination: PremiumIntroView()) {
                                    HStack {
                                        Text("次へ")
                                    }
                                    .fontWeight(.semibold)
                                    .frame(width: 300, height: 50)
                                    .background(isAgreed ? Color.blue : Color(.systemGray4))
                                    .foregroundStyle(isAgreed ? .white : .white.opacity(0.6))
                                    .cornerRadius(10)
                                }
                                .disabled(!isAgreed) // 同意していない場合はボタンを無効化
                                .simultaneousGesture(TapGesture().onEnded {
                                    // ★ 遷移する瞬間にカレンダーの許可をリクエストする
                                    Task {
                                        let granted = await appState.calendarManager.requestAccess()
                                        await MainActor.run {
                                            appState.userData.calendarLinked = granted
                                            appState.save()
                                        }
                                    }
                                })
                                
                                // --- スキップボタン ---
                               
            }
            .padding()
            .navigationBarBackButtonHidden(true)
            
            // ★ 修正：NotionのURLを実際に開くための設定
            .sheet(isPresented: $isShowingTerms) {
                SafariView(url: URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80569a9ecd81dfe84d11?source=copy_link")!)
            }
            .sheet(isPresented: $isShowingPrivacyPolicy) {
                SafariView(url: URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80e59cb0c9bd2fb0c008")!)
            }
        }
    }
}

// ★ アプリ内でWebページを安全に表示するための部品 (SafariView)
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
