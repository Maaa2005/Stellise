import Foundation
import AVFoundation
import Combine
@preconcurrency import TensorFlowLite

/// TensorFlow Liteの状態を専用キューへ閉じ込める。
/// InterpreterはSendableではないため、読み込み完了後の操作を専用キューに直列化する。
private final class SoundInferenceWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.stellise.TFLiteAnalysisQueue")
    private let interpreter: Interpreter
    private let classNames: [String]
    private let requiredSampleCount = 15_600
    private var audioBuffer: [Float] = []

    private init(interpreter: Interpreter, classNames: [String]) {
        self.interpreter = interpreter
        self.classNames = classNames
    }

    static func load() async throws -> SoundInferenceWorker {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "com.stellise.TFLiteLoader", qos: .userInitiated).async {
                do {
                    guard let modelPath = Bundle.main.path(forResource: "yamnet", ofType: "tflite") else {
                        throw NSError(domain: "SoundAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "yamnet.tflite が見つかりません。"])
                    }
                    guard let labelsPath = Bundle.main.path(forResource: "yamnet", ofType: "txt") else {
                        throw NSError(domain: "SoundAnalyzer", code: 2, userInfo: [NSLocalizedDescriptionKey: "yamnet.txt が見つかりません。"])
                    }

                    let interpreter = try Interpreter(modelPath: modelPath)
                    try interpreter.allocateTensors()
                    let labels = try parseLabels(at: labelsPath)
                    continuation.resume(returning: SoundInferenceWorker(interpreter: interpreter, classNames: labels))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func append(_ samples: [Float], onDetection: @escaping @Sendable (String, Float) -> Void) {
        queue.async { [self] in
            audioBuffer.append(contentsOf: samples)
            while audioBuffer.count >= requiredSampleCount {
                let chunk = Array(audioBuffer.prefix(requiredSampleCount))
                audioBuffer.removeFirst(requiredSampleCount)
                if let detection = analyze(chunk) {
                    onDetection(detection.label, detection.score)
                }
            }
        }
    }

    func reset() {
        queue.async { [self] in audioBuffer.removeAll(keepingCapacity: true) }
    }

    private func analyze(_ audioData: [Float]) -> (label: String, score: Float)? {
        do {
            let tensorData = audioData.withUnsafeBufferPointer { Data(buffer: $0) }
            try interpreter.copy(tensorData, toInputAt: 0)
            try interpreter.invoke()

            let output = try interpreter.output(at: 0)
            let scores = output.data.withUnsafeBytes {
                Array(UnsafeBufferPointer<Float32>(
                    start: $0.baseAddress?.assumingMemoryBound(to: Float32.self),
                    count: classNames.count
                ))
            }
            guard let (index, score) = scores.enumerated().max(by: { $0.1 < $1.1 }),
                  index < classNames.count,
                  score > 0.4 else { return nil }

            let label = classNames[index]
            guard ["Snoring", "Cough", "Speech", "Gasp"].contains(label) else { return nil }
            return (label, score)
        } catch {
            debugLog("❌ TFLite 推論エラー: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseLabels(at path: String) throws -> [String] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return content.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            var columns: [String] = []
            var current = ""
            var inQuotes = false
            for character in line {
                if character == "\"" {
                    inQuotes.toggle()
                } else if character == "," && !inQuotes {
                    columns.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            }
            columns.append(current)
            guard columns.count > 2 else { return nil }
            return columns[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }
}

private final class ConverterInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var delivered = false

    func shouldProvideInput() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !delivered else { return false }
        delivered = true
        return true
    }
}

@MainActor
final class SoundAnalyzer: NSObject, ObservableObject {
    @Published var lastDetectedSound: String?
    @Published private(set) var isAnalyzing = false

    private var audioEngine: AVAudioEngine?
    private var worker: SoundInferenceWorker?
    private var lifecycleID = UUID()
    private let sampleRate = 16_000.0

    override init() {
        super.init()
        debugLog("SoundAnalyzerが初期化されました。")
    }

    func startAnalyzing() async {
        guard !isAnalyzing else { return }
        let runID = UUID()
        lifecycleID = runID

        let permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in continuation.resume() }
            }
        }
        guard lifecycleID == runID,
              AVAudioApplication.shared.recordPermission == .granted else {
            debugLog("❌ マイクの許可がないか、開始処理がキャンセルされました。")
            return
        }

        do {
            debugLog("TFLite: モデルとラベルの非同期ロードを開始します...")
            let loadedWorker = try await SoundInferenceWorker.load()
            guard lifecycleID == runID else { return }
            worker = loadedWorker

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                throw NSError(domain: "SoundAnalyzer", code: 3, userInfo: [NSLocalizedDescriptionKey: "音声フォーマットを変換できません。"])
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self, loadedWorker] buffer, _ in
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (16_000.0 / inputFormat.sampleRate))
                guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
                let state = ConverterInputState()
                var conversionError: NSError?
                converter.convert(to: converted, error: &conversionError) { _, status in
                    guard state.shouldProvideInput() else {
                        status.pointee = .noDataNow
                        return nil
                    }
                    status.pointee = .haveData
                    return buffer
                }
                guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return }
                let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
                loadedWorker.append(samples) { label, score in
                    Task { @MainActor [weak self] in
                        guard let self, self.lifecycleID == runID else { return }
                        debugLog("⚠️ TFLite イベント検出: \(label) (信頼度: \(score * 100)%)")
                        self.lastDetectedSound = label
                    }
                }
            }

            audioEngine = engine
            engine.prepare()
            try engine.start()
            guard lifecycleID == runID else {
                stopAnalyzing()
                return
            }
            isAnalyzing = true
            debugLog("🎙 音声分析(YAMNet)をバックグラウンドで開始しました")
        } catch {
            guard lifecycleID == runID else { return }
            stopAnalyzing()
            debugLog("❌ 音声分析の開始に失敗: \(error.localizedDescription)")
        }
    }

    func stopAnalyzing() {
        lifecycleID = UUID()
        isAnalyzing = false
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        worker?.reset()
        worker = nil
        debugLog("⏸️ 音声分析 (TFLite) を停止しました。")
    }
}
