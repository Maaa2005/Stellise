import Foundation
import StoreKit
import FirebaseFirestore
import FirebaseAuth
import Combine

enum ProductID: String, CaseIterable {
    // ★ App Store Connectで登録する製品ID（プロダクトID）と完全に一致させること
    case proMonthly = "com.yuutokiwai.Stellise.pro.monthly.v1"
}

@MainActor
class SubscriptionManager: ObservableObject {
    @Published var isPremium: Bool = false
    @Published var products: [Product] = []
    
    // デバッグ用フラグ
    @Published var isDebugModeEnabled: Bool = false
    
    private let db = Firestore.firestore()
    
    // バックグラウンドでの課金状態監視用タスク
    private var updateListenerTask: Task<Void, Never>? = nil
    
    init() {
        // ★ 審査通過の絶対条件: アプリ起動時からバックグラウンドでトランザクションを監視する
        updateListenerTask = listenForTransactions()
        
        Task {
            await loadProducts()
            await updateStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // ==========================================
    // MARK: - トランザクション監視 (プロモコード対応の要)
    // ==========================================
    
    /// アプリ外（App Storeや設定アプリ）でプロモコードが使われたり、
    /// サブスクが更新・解約されたりした時の変更をリアルタイムに受け取る
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    // トランザクションを完了させる (これをしないと未処理として残り続ける)
                    await transaction.finish()
                    // 状態を最新に更新
                    await self.updateStatus()
                } catch {
                    print("❌ トランザクションの検証に失敗しました")
                }
            }
        }
    }
    
    // ==========================================
    // MARK: - 商品取得と購入処理
    // ==========================================
    
    /// App Storeから商品情報(価格など)を取得する
    func loadProducts() async {
        do {
            self.products = try await Product.products(for: ProductID.allCases.map { $0.rawValue })
        } catch {
            print("❌ StoreKit 読み込みエラー: \(error)")
        }
    }
    
    /// ユーザーが購入ボタンを押した時の処理
    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateStatus()
                
            case .userCancelled, .pending:
                print("購入がキャンセルされたか、保留中です")
                break
            @unknown default:
                break
            }
        } catch {
            print("❌ 購入処理中にエラー発生: \(error)")
        }
    }
    
    // ==========================================
    // MARK: - ステータス確認と復元
    // ==========================================
    
    /// 現在プレミアムプランが有効かどうかを確認する
    func updateStatus() async {
        if isDebugModeEnabled {
            print("🔧 Debug Mode: 強制的にプレミアムをONにします")
            self.isPremium = true
            return
        }
        
        var active = false
        
        // 1. StoreKit 2 で現在の有効なサブスクリプションを確認
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                // 自動更新サブスクリプションが有効な場合
                if transaction.productType == .autoRenewable || transaction.productType == .nonRenewable {
                    active = true
                }
            } catch {
                print("❌ 無効なトランザクションをスキップしました")
            }
        }
        
        // 2. Fallback: StoreKitで確認できなければFirestoreを確認 (クロスプラットフォーム対応用)
        if !active, let user = Auth.auth().currentUser {
            if let doc = try? await db.collection("users").document(user.uid).getDocument(),
               let isPrem = doc.data()?["isPremium"] as? Bool, isPrem {
                active = true
            }
        }
        
        // メインスレッドでUIを更新
        self.isPremium = active
        print("👑 プレミアム状態チェック: \(active ? "有効" : "無効")")
    }
    
    /// 機種変更時などの「購入の復元」処理
    func restore() async {
        do {
            // AppStore.sync() は強制的にApp Storeと通信し、レシート情報を最新にする(iOS 15+)
            try await AppStore.sync()
            await updateStatus()
            print("✅ 購入の復元が完了しました")
        } catch {
            print("❌ 購入の復元に失敗: \(error)")
        }
    }
    
    // ==========================================
    // MARK: - ヘルパー関数
    // ==========================================
    
    /// トランザクションがAppleによって暗号的に署名・検証されているかチェックする
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            // 脱獄端末や不正なレシートによる偽造を防ぐ
            throw error
        case .verified(let safe):
            return safe
        }
    }
}
