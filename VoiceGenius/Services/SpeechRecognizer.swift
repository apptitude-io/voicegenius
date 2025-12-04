import AVFoundation
import Speech
import Foundation

/// Service for on-device speech recognition with VAD (Voice Activity Detection)
final class SpeechRecognizer: @unchecked Sendable {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    private(set) var transcript: String = ""
    private(set) var isListening = false

    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.2  // VAD: 1.2s silence ends utterance
    private var lastSpeechTime: Date = Date()

    var onUtteranceComplete: (@Sendable (String) -> Void)?
    var onTranscriptUpdate: (@Sendable (String) -> Void)?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer?.supportsOnDeviceRecognition = true
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() throws {
        // Cancel any existing task
        stopListening()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcriptText = result.bestTranscription.formattedString
                self.transcript = transcriptText
                self.lastSpeechTime = Date()

                // Notify on main thread
                let handler = self.onTranscriptUpdate
                DispatchQueue.main.async {
                    handler?(transcriptText)
                }
            }

            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.finalizeUtterance()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        lastSpeechTime = Date()
        startSilenceDetection()
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    private func startSilenceDetection() {
        DispatchQueue.main.async { [weak self] in
            self?.silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.checkForSilence()
            }
        }
    }

    private func checkForSilence() {
        let silenceDuration = Date().timeIntervalSince(lastSpeechTime)

        if silenceDuration >= silenceThreshold && !transcript.isEmpty {
            finalizeUtterance()
        }
    }

    private func finalizeUtterance() {
        guard !transcript.isEmpty else { return }

        let finalTranscript = transcript
        stopListening()
        transcript = ""

        let handler = onUtteranceComplete
        handler?(finalTranscript)
    }
}
