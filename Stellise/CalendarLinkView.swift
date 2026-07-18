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
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingProgressHeader(step: 5, total: 5)

                ScrollView {
                    VStack(spacing: 24) {
                        OnboardingHero(
                            symbol: "calendar.badge.plus",
                            title: "カレンダー連携",
                            description: "予定と移動時間から、必要な起床時刻を自動で計算できます。"
                        )
                        .padding(.top, 30)

                        VStack(alignment: .leading, spacing: 16) {
                            calendarBenefit(icon: "clock.fill", text: "予定に合わせて起床時刻を提案")
                            calendarBenefit(icon: "arrow.triangle.turn.up.right.diamond.fill", text: "移動時間を含めて出発時刻を計算")
                            calendarBenefit(icon: "lock.shield.fill", text: "アクセスはいつでも設定から変更可能")
                        }
                        .onboardingCard()

                        Button { isAgreed.toggle() } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: isAgreed ? "checkmark.square.fill" : "square")
                                    .font(.title2)
                                    .foregroundStyle(isAgreed ? Theme.Palette.accentLight : .white.opacity(0.45))

                                Text("利用規約とプライバシーポリシーを確認し、Stelliseの利用を開始することに同意します。")
                                    .font(.footnote)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .onboardingCard()

                        HStack(spacing: 20) {
                            Button("利用規約") { isShowingTerms = true }
                            Button("プライバシーポリシー") { isShowingPrivacyPolicy = true }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.accentLight)

                        VStack(spacing: 14) {
                            Button {
                                guard !isRequestingAccess else { return }
                                isRequestingAccess = true
                                Task {
                                    let granted = await appState.calendarManager.requestAccess()
                                    await MainActor.run {
                                        appState.userData.calendarLinked = granted
                                        appState.save()
                                        isRequestingAccess = false
                                        navigateNext = true
                                    }
                                }
                            } label: {
                                OnboardingPrimaryLabel(
                                    title: "カレンダーを連携",
                                    isEnabled: isAgreed,
                                    isLoading: isRequestingAccess
                                )
                            }
                            .buttonStyle(PressSpringButtonStyle())
                            .disabled(!isAgreed || isRequestingAccess)

                            Button {
                                appState.userData.calendarLinked = false
                                appState.save()
                                navigateNext = true
                            } label: {
                                Text("今は連携しない")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(isAgreed ? Theme.Palette.textOnDarkMuted : .white.opacity(0.28))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(!isAgreed || isRequestingAccess)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationDestination(isPresented: $navigateNext) { PremiumIntroView() }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingTerms) {
            SafariView(url: URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80569a9ecd81dfe84d11?source=copy_link")!)
        }
        .sheet(isPresented: $isShowingPrivacyPolicy) {
            SafariView(url: URL(string: "https://dusty-jobaria-c70.notion.site/Stellise-3297d70e2c8c80e59cb0c9bd2fb0c008")!)
        }
    }

    private func calendarBenefit(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .frame(width: 34, height: 34)
                .background(Theme.Palette.accent.opacity(0.18), in: Circle())
                .foregroundStyle(Theme.Palette.accentLight)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
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
