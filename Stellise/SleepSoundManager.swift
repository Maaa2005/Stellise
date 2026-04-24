import AVFoundation
import SwiftUI
import Combine // ★★★ これが必須です ★★★

class SleepSoundManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    @Published var isPlaying = false
    @Published var remainingTime: TimeInterval?
    
    // 現在選択されている音
    @Published var selectedSound: SleepSound = .bonfire
    
    // 音の種類の定義
    enum SleepSound: String, CaseIterable, Identifiable {
        case bonfire = "焚き火"
        case waves = "さざ波"
        case rain = "雨音"
        
        var id: String { self.rawValue }
        
        var fileName: String {
            switch self {
            case .bonfire: return "bonfire"
            case .waves: return "waves"
            case .rain: return "rain"
            }
        }
    }

    init() {
        setupSession()
    }

    private func setupSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ AVAudioSession設定失敗: \(error)")
        }
    }

    // ==========================================
    // MARK: - 再生・停止
    // ==========================================
    
    func togglePlay(premium: Bool, timerDuration: TimeInterval?) {
        if isPlaying {
            stopSound()
        } else {
            playSound(premium: premium, timerDuration: timerDuration)
        }
    }
    
    func playSound(premium: Bool, timerDuration: TimeInterval?) {
        if !premium {
            print("⚠️ プレミアム限定音声です")
            return
        }

        stopSound()

        // プロジェクト内からmp3ファイルを探す
        guard let url = Bundle.main.url(forResource: selectedSound.fileName, withExtension: "mp3") else {
            print("❌ 音声ファイルが見つかりません: \(selectedSound.fileName).mp3 をXcodeに追加してください")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // 無限ループ再生
            audioPlayer?.volume = 0.3 // 睡眠の邪魔にならない音量
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            
            isPlaying = true
            print("🔊 \(selectedSound.rawValue)の再生を開始しました")

            if let duration = timerDuration {
                startSleepTimer(duration: duration)
            }
        } catch {
            print("❌ 音声の再生に失敗しました: \(error)")
        }
    }

    func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        stopSleepTimer()
        print("🔇 睡眠音再生停止")
    }

    // ==========================================
    // MARK: - スリープタイマーロジック
    // ==========================================
    
    private func startSleepTimer(duration: TimeInterval) {
            remainingTime = duration
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self, let remaining = self.remainingTime else { return }
                self.remainingTime = remaining - 1
                
                // ★★★ 修正: 危険な「!」を排除し、安全にゼロを判定する ★★★
                if let currentTime = self.remainingTime, currentTime <= 0 {
                    self.stopSound()
                }
            }
        }
    
    private func stopSleepTimer() {
        timer?.invalidate()
        timer = nil
        remainingTime = nil
    }
}
