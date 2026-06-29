import AVFoundation
import SwiftUI
import Combine

class SleepSoundManager: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    @Published var isPlaying = false
    @Published var remainingTime: TimeInterval?
    @Published var selectedSound: SleepSound = .bonfire

    enum SleepSound: String, CaseIterable, Identifiable {
        case bonfire = "焚き火"
        case waves   = "さざ波"
        case rain    = "雨音"

        var id: String { rawValue }

        var fileName: String {
            switch self {
            case .bonfire: return "bonfire"
            case .waves:   return "waves"
            case .rain:    return "rain"
            }
        }
    }

    // MARK: - 再生・停止

    func togglePlay(timerDuration: TimeInterval?) {
        if isPlaying { stopSound() } else { playSound(timerDuration: timerDuration) }
    }

    func playSound(timerDuration: TimeInterval?) {
        stopSound()

        // 再生直前にセッションを正しいカテゴリに設定
        activatePlaybackSession()

        guard let url = Bundle.main.url(forResource: selectedSound.fileName, withExtension: "mp3") else {
            print("❌ 音声ファイルが見つかりません: \(selectedSound.fileName).mp3")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.volume = 0.35
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            isPlaying = true
            print("🔊 \(selectedSound.rawValue) 再生開始")

            if let duration = timerDuration {
                startSleepTimer(duration: duration)
            }
        } catch {
            print("❌ 音声の再生に失敗: \(error)")
        }
    }

    func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        stopSleepTimer()
        print("🔇 睡眠音停止")
    }

    // アラーム鳴動前に AppState から呼ぶ（セッションを alarm 用に戻す）
    func prepareForAlarm() {
        stopSound()
    }

    // MARK: - Private

    private func activatePlaybackSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ SleepSoundManager: AVAudioSession設定失敗: \(error)")
        }
    }

    // MARK: - スリープタイマー

    private func startSleepTimer(duration: TimeInterval) {
        remainingTime = duration
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let remaining = self.remainingTime else { return }
            self.remainingTime = remaining - 1
            if let t = self.remainingTime, t <= 0 { self.stopSound() }
        }
    }

    private func stopSleepTimer() {
        timer?.invalidate()
        timer = nil
        remainingTime = nil
    }
}
