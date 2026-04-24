import Foundation
import CoreMotion
import Combine

@MainActor
class SensorManager: ObservableObject {
    
    private let motionManager = CMMotionManager()
    private var lastMagnitude: Double = 0.0
    
    // UI側で監視するためのプロパティ
    @Published var isDetecting: Bool = false
    @Published var isFaceDown: Bool = false // ★ これが省電力のトリガーになります
    
    // コールバック (AppStateへ通知用)
    var onMovementDetected: ((_ intensity: Double) -> Void)?
    
    // バックグラウンド処理用キュー
    private let queue = OperationQueue()
    
    init() {
        // 加速度センサーが使えるかチェック
        if !motionManager.isAccelerometerAvailable {
            print("【SensorManager】エラー: 加速度センサーが利用できません。")
        }
        // 更新頻度 (0.5秒ごとにチェック)
        motionManager.accelerometerUpdateInterval = 0.5
        queue.maxConcurrentOperationCount = 1
    }
    
    /// 検知開始
    func startDetection(threshold: Double) {
        guard !isDetecting else { return }
        
        // フラグをオン
        self.isDetecting = true
        self.lastMagnitude = 0.0
        
        print("【SensorManager】センサー検知を開始しました。(閾値: \(threshold))")
        
        // 加速度データの取得開始
        motionManager.startAccelerometerUpdates(to: self.queue) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }
            
            // 1. 体動検知 (睡眠の深さ判定用)
            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            
            let magnitude = sqrt(x*x + y*y + z*z)
            let intensity = (self.lastMagnitude == 0.0) ? 0.0 : abs(magnitude - self.lastMagnitude)
            self.lastMagnitude = magnitude
            
            // 2. うつ伏せ判定 (Z軸が正の方向＝画面が下)
            // 機種によって多少異なりますが、一般的に z > 0.9 でほぼ真下を向いています
            let currentIsFaceDown = (z > 0.85)
            
            // メインスレッドでUI/ロジックに通知
            Task { @MainActor in
                guard self.isDetecting else { return }
                
                // 体動が閾値を超えたら通知
                if intensity > threshold {
                    self.onMovementDetected?(intensity)
                }
                
                // うつ伏せ状態が変わったら通知 (省電力モード切替)
                if self.isFaceDown != currentIsFaceDown {
                    self.isFaceDown = currentIsFaceDown
                    print("📱 向き変更: \(currentIsFaceDown ? "うつ伏せ (省電力ON)" : "仰向け (通常)")")
                }
            }
        }
    }
    
    /// 検知停止
    func stopDetection() {
        guard isDetecting else { return }
        
        self.isDetecting = false
        self.motionManager.stopAccelerometerUpdates()
        print("【SensorManager】センサー検知を停止しました。")
    }
}
