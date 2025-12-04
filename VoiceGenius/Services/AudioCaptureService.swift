import AVFoundation
import Foundation

/// Service for capturing audio from the microphone and calculating amplitude
final class AudioCaptureService: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var amplitudeUpdateHandler: ((Float) -> Void)?

    private(set) var isCapturing = false

    init() {}

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startCapturing(onAmplitudeUpdate: @escaping @Sendable (Float) -> Void) throws {
        self.amplitudeUpdateHandler = onAmplitudeUpdate

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try audioSession.setActive(true)

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        inputNode = audioEngine.inputNode
        guard let inputNode = inputNode else { return }

        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isCapturing = true
    }

    func stopCapturing() {
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isCapturing = false
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        // Calculate RMS (Root Mean Square) for amplitude
        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))

        // Normalize to 0.0 - 1.0 range (with some headroom)
        let normalizedAmplitude = min(1.0, rms * 5.0)

        // Dispatch to main thread for UI updates
        let handler = self.amplitudeUpdateHandler
        DispatchQueue.main.async {
            handler?(normalizedAmplitude)
        }
    }
}
