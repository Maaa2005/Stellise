import SwiftUI
import SafariServices // ★ブラウザを表示するために追加

struct CalendarLinkView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var isAgreed = false
    @State private var isShowingPrivacyPolicy = false
    @State private var isShowingTerms = false
    @State private var navigateNext = false
    @State private var isRequestingAccess = false
    
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
                    .foregroundStyle(.appAccent)
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
                                .foregroundStyle(isAgreed ? .appAccent : .gray)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 0) {
                                Button("利用規約") { isShowingTerms = true }
                                    .foregroundStyle(.appAccent)
                                Text(" と ")
                                Button("プライバシーポリシー") { isShowingPrivacyPolicy = true }
                                    .foregroundStyle(.appAccent)
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
                // ※NavigationLink+simultaneousGestureだと権限ダイアログと画面遷移が同時に走り、
                //   課金画面の上にポップアップが被さる。「許可に応答してから遷移」に変更。
                                Button {
                                    guard !isRequestingAccess else { return }
                                    isRequestingAccess = true
                                    Task {
                                        let granted = await appState.calendarManager.requestAccess()
                                        await MainActor.run {
                                            appState.userData.calendarLinked = granted
                                            appState.save()
                                            isRequestingAccess = false
                                            navigateNext = true // ダイアログ応答後に遷移
                                        }
                                    }
                                } label: {
                                    HStack {
                                        if isRequestingAccess {
                                            ProgressView().tint(.white)
                                        }
                                        Text("次へ")
                                    }
                                    .fontWeight(.semibold)
                                    .frame(width: 300, height: 50)
                                    .background(isAgreed ? Color.appAccent : Color(.systemGray4))
                                    .foregroundStyle(isAgreed ? .white : .white.opacity(0.6))
                                    .cornerRadius(10)
                                }
                                .disabled(!isAgreed || isRequestingAccess)

                                // --- スキップボタン ---
                                // カレンダー連携を強制しない（権限ダイアログなしで次へ進める）。
                                // 連携は後から設定画面でいつでも許可できる。
                                Button {
                                    appState.userData.calendarLinked = false
                                    appState.save()
                                    navigateNext = true
                                } label: {
                                    Text("今は連携しない")
                                        .font(.callout)
                                        .foregroundStyle(isAgreed ? .secondary : Color(.systemGray4))
                                }
                                .disabled(!isAgreed || isRequestingAccess) // 規約同意は必須
            }
            .navigationDestination(isPresented: $navigateNext) {
                PremiumIntroView()
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
