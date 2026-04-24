import Foundation
import AVFoundation
import Combine
import TensorFlowLite

@MainActor
class SoundAnalyzer: NSObject, ObservableObject {
    
    @Published var lastDetectedSound: String? = nil
    @Published var isAnalyzing: Bool = false
    
    private var interpreter: Interpreter?
    private var classNames: [String] = []

    private var audioEngine: AVAudioEngine?
    private let analysisQueue = DispatchQueue(label: "com.stellise.TFLiteAnalysisQueue")

    private let sampleRate = 16000.0
    private let requiredSampleCount = 15600
    private var audioBuffer: [Float] = []
    
    private var isModelLoaded = false
    private var debugCounter = 0

    override init() {
        super.init()
        print("SoundAnalyzerが初期化されました。")
    }

    private func loadModelAndLabels() async throws {
        guard !isModelLoaded else { return }
        
        print("TFLite: モデルとラベルの非同期ロードを開始します...")
        
        try await Task(priority: .userInitiated) {
            
            guard let modelPath = Bundle.main.path(forResource: "yamnet", ofType: "tflite") else {
                throw NSError(domain: "SoundAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "yamnet.tflite が見つかりません。"])
            }
            let interpreter = try Interpreter(modelPath: modelPath)
            try interpreter.allocateTensors()
            
            guard let labelsPath = Bundle.main.path(forResource: "yamnet", ofType: "txt") else {
                throw NSError(domain: "SoundAnalyzer", code: 2, userInfo: [NSLocalizedDescriptionKey: "yamnet.txt が見つかりません。"])
            }
            let content = try String(contentsOfFile: labelsPath, encoding: .utf8)
            var classNames: [String] = []

            var lineIndex = 0
            content.enumerateLines { line, _ in
                guard lineIndex > 0 else {
                    lineIndex += 1
                    return
                }
                
                var columns: [String] = []
                var currentColumn = ""
                var inQuotes = false
                
                for char in line {
                    if char == "\"" {
                        inQuotes.toggle()
                    } else if char == "," && !inQuotes {
                        columns.append(currentColumn)
                        currentColumn = ""
                    } else {
                        currentColumn.append(char)
                    }
                }
                columns.append(currentColumn)
                
                if columns.count > 2 {
                    let className = columns[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    classNames.append(className)
                }
                lineIndex += 1
            }

            self.analysisQueue.async {
                self.interpreter = interpreter
                self.classNames = classNames
                self.isModelLoaded = true
                
                DispatchQueue.main.async {
                    print("✅ TFLite: モデルとラベルのロードに成功しました。 (\(classNames.count) 件)")
                }
            }
        }.value
    }
    
    // ==========================================
        // MARK: - 音声分析の開始 (ダウンサンプリング対応版)
        // ==========================================
        func startAnalyzing() async {
            let permission = AVAudioSession.sharedInstance().recordPermission
                    if permission == .undetermined {
                        await withCheckedContinuation { continuation in
                            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                                continuation.resume()
                            }
                        }
                    }
                    
            guard AVAudioSession.sharedInstance().recordPermission == .granted else {
                print("❌ マイクの許可がありません。音声解析を中止します。")
                return
                
            }
            
            do {
                try await loadModelAndLabels()
                
                // エンジンの初期化
                audioEngine = AVAudioEngine()
                guard let audioEngine = audioEngine else { return }
                
                let inputNode = audioEngine.inputNode
                // ★ポイント1: マイクの「実際の」フォーマットを取得する
                let inputFormat = inputNode.outputFormat(forBus: 0)
                
                // ★ポイント2: AIが要求するフォーマット (16kHz, 1ch) を定義する
                guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else {
                    print("❌ ターゲットフォーマットの作成に失敗")
                    return
                }
                
                // ★ポイント3: 変換器 (Converter) を作成
                guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                    print("❌ AVAudioConverterの作成に失敗。フォーマットがサポートされていません。")
                    return
                }
                
                inputNode.removeTap(onBus: 0)
                
                // ★ポイント4: マイクからのデータ取得は「元のフォーマット」で行う
                inputNode.installTap(onBus: 0, bufferSize: 8192, format: inputFormat) { [weak self] (buffer, time) in
                    guard let self = self else { return }
                    
                    // 変換後のバッファサイズを計算して箱を用意する
                    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (self.sampleRate / inputFormat.sampleRate))
                    guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
                    
                    var error: NSError?
                    var allSamplesReceived = false
                    
                    // 変換器にデータを流し込む処理
                    let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                        if allSamplesReceived {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                        allSamplesReceived = true
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    
                    // 変換を実行！ (44.1kHz -> 16kHz)
                    converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
                    
                    // 変換された16kHzのデータをFloat配列にする
                    if let channelData = convertedBuffer.floatChannelData?[0] {
                        let frameLength = Int(convertedBuffer.frameLength)
                        let dataArray = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                        
                        // バックグラウンドでAIに渡す準備
                        self.analysisQueue.async {
                            self.audioBuffer.append(contentsOf: dataArray)
                            
                            // 必要なサンプル数 (15600) が溜まったらAIに推論させる
                            if self.audioBuffer.count >= self.requiredSampleCount {
                                let chunkToAnalyze = Array(self.audioBuffer.prefix(self.requiredSampleCount))
                                // 処理した分だけバッファから消す
                                self.audioBuffer.removeFirst(self.requiredSampleCount)
                                
                                // YAMNetの推論メソッドを呼ぶ
                                self.analyzeAudioChunk(audioData: chunkToAnalyze)
                            }
                        }
                    }
                }
                
                audioEngine.prepare()
                try audioEngine.start()
                
                DispatchQueue.main.async {
                    self.isAnalyzing = true
                }
                print("🎙 音声分析(YAMNet)をバックグラウンドで開始しました")
                
            } catch {
                print("❌ 音声分析の開始に失敗: \(error)")
            }
        }

    func stopAnalyzing() {
        guard isAnalyzing else { return }
        
        self.isAnalyzing = false
        
        analysisQueue.async {
            self.audioEngine?.stop()
            self.audioEngine?.inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            self.audioBuffer = []
            
            DispatchQueue.main.async {
                print("⏸️ 音声分析 (TFLite) を停止しました。")
            }
        }
    }

    private func analyzeAudioChunk(audioData: [Float]) {
        guard let interpreter = self.interpreter else { return }
        
        debugCounter += 1
        
        let audioTensorData = audioData.withUnsafeBufferPointer { Data(buffer: $0) }
        
        do {
            try interpreter.copy(audioTensorData, toInputAt: 0)
            try interpreter.invoke()
            
            let outputTensor = try interpreter.output(at: 0)
            
            let outputScores = outputTensor.data.withUnsafeBytes {
                Array(UnsafeBufferPointer<Float32>(start: $0.baseAddress!.assumingMemoryBound(to: Float32.self), count: self.classNames.count))
            }
            
            guard let (maxIndex, maxScore) = outputScores.enumerated().max(by: { $0.1 < $1.1 }),
                  maxIndex < self.classNames.count else {
                return
            }
            
            let detectedLabel = self.classNames[maxIndex]

            if maxScore > 0.4 {
                if ["Snoring", "Cough", "Speech", "Gasp"].contains(detectedLabel) {
                    DispatchQueue.main.async {
                        print("⚠️ TFLite イベント検出: \(detectedLabel) (信頼度: \(maxScore * 100)%)")
                        self.lastDetectedSound = detectedLabel
                    }
                }
            }
            
        } catch {
            DispatchQueue.main.async {
                print("❌ TFLite 推論エラー: \(error.localizedDescription)")
            }
        }
    }
}
