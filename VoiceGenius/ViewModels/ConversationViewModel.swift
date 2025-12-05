import SwiftUI
import Combine

/// Main view model orchestrating the conversation loop
@MainActor
@Observable
final class ConversationViewModel {
    // State
    var state: ConversationState = .idle
    var amplitude: Float = 0.0
    var currentTranscript: Transcript = Transcript()
    var isSessionActive = false
    var errorMessage: String?
    var modelName: String?

    // Model switching state
    var isSwitchingModel = false

    // Download state (observed from ModelDownloader)
    var isCheckingModel = true

    var downloadState: ModelDownloadState {
        modelDownloader.state
    }

    var isDownloading: Bool {
        modelDownloader.state.isActive
    }

    var downloadProgressText: String {
        modelDownloader.progressText
    }

    var isOnCellular: Bool {
        modelDownloader.isOnCellular
    }

    /// Current backend being used
    var currentBackend: LLMBackend {
        SettingsViewModel.shared.backend
    }

    // Services
    private var llmService: LLMService
    private let audioCapture: AudioCaptureService
    private let speechRecognizer: SpeechRecognizer
    private let speechSynthesizer: SpeechSynthesizer
    let modelDownloader: ModelDownloader
    let transcriptStore: TranscriptStore

    // Sine wave animation for speaking state
    private var speakingAnimationPhase: Double = 0.0
    private var speakingTimer: Timer?

    init() {
        self.llmService = LLMFactory.create()
        self.audioCapture = AudioCaptureService()
        self.speechRecognizer = SpeechRecognizer()
        self.speechSynthesizer = SpeechSynthesizer()
        self.modelDownloader = ModelDownloader()
        self.transcriptStore = TranscriptStore()

        setupCallbacks()
    }

    // MARK: - Model Hot-Swap

    /// Reinitialize the LLM service with current settings
    /// Call this when backend or model selection changes
    func reinitializeLLMService() async {
        guard !isSessionActive else {
            errorMessage = "Cannot switch models during an active session"
            return
        }

        isSwitchingModel = true
        errorMessage = nil

        // Unload current model to free memory
        if let managedService = llmService as? ManagedLLMService {
            await managedService.unload()
        }

        // Create new service based on current settings
        llmService = LLMFactory.create()

        // Initialize the new service
        await checkModelAndInitialize()

        isSwitchingModel = false
    }

    private func setupCallbacks() {
        // Handle completed utterances from speech recognizer
        speechRecognizer.onUtteranceComplete = { [weak self] text in
            Task { @MainActor in
                await self?.handleUserUtterance(text)
            }
        }

        // Handle TTS events
        speechSynthesizer.onSpeechStarted = { [weak self] in
            Task { @MainActor in
                self?.state = .speaking
                self?.startSpeakingAnimation()
            }
        }

        speechSynthesizer.onSpeechFinished = { [weak self] in
            Task { @MainActor in
                self?.stopSpeakingAnimation()
                self?.continueListening()
            }
        }
    }

    // MARK: - Initialization

    func checkModelAndInitialize() async {
        isCheckingModel = true
        let settings = SettingsViewModel.shared

        // Handle Foundation backend
        if settings.backend == .foundation {
            if FoundationLLMService.isAvailable {
                modelName = "Apple Intelligence"
                isCheckingModel = false
                return
            } else {
                errorMessage = "Apple Intelligence not available on this device"
                isCheckingModel = false
                return
            }
        }

        // Handle MLX backend
        #if targetEnvironment(simulator)
        // On simulator, check if sidecar is running
        if let sidecarService = llmService as? SidecarLLMService {
            let (isRunning, _) = await sidecarService.healthCheck()
            if isRunning {
                modelName = settings.selectedPreset.name
            } else {
                errorMessage = "Sidecar server not running. Start it with: python sidecar/sidecar.py"
            }
        }
        isCheckingModel = false
        #else
        // On device, check if model is downloaded
        if !modelDownloader.isModelDownloaded() {
            isCheckingModel = false
            await downloadModel()
        } else {
            // Load the model
            if let deviceService = llmService as? OnDeviceLLMService {
                do {
                    try await deviceService.loadModel()
                    modelName = settings.selectedPreset.name
                } catch {
                    errorMessage = "Failed to load model: \(error.localizedDescription)"
                }
            }
            isCheckingModel = false
        }
        #endif
    }

    func downloadModel() async {
        do {
            try await modelDownloader.downloadModel()

            // Load the model after download
            if let deviceService = llmService as? OnDeviceLLMService {
                try await deviceService.loadModel()
                modelName = modelDownloader.modelName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelDownload() {
        modelDownloader.cancelDownload()
    }

    // MARK: - Session Control

    func startSession() async {
        guard !isSessionActive else { return }

        // Request permissions
        let micPermission = await audioCapture.requestPermission()
        let speechPermission = await speechRecognizer.requestPermission()

        guard micPermission && speechPermission else {
            errorMessage = "Microphone and speech recognition permissions are required"
            return
        }

        isSessionActive = true
        currentTranscript = Transcript()
        errorMessage = nil

        startListening()
    }

    func endSession() {
        stopListening()
        speechSynthesizer.stop()
        stopSpeakingAnimation()

        // Save transcript if it has content
        if !currentTranscript.turns.isEmpty {
            do {
                try transcriptStore.save(currentTranscript)
            } catch {
                print("Failed to save transcript: \(error)")
            }
        }

        isSessionActive = false
        state = .idle
        amplitude = 0.0
    }

    // MARK: - Listening

    private func startListening() {
        state = .listening

        do {
            try audioCapture.startCapturing { [weak self] amp in
                Task { @MainActor in
                    self?.amplitude = amp
                }
            }
            try speechRecognizer.startListening()
        } catch {
            errorMessage = "Failed to start listening: \(error.localizedDescription)"
            state = .idle
        }
    }

    private func stopListening() {
        audioCapture.stopCapturing()
        speechRecognizer.stopListening()
    }

    private func continueListening() {
        guard isSessionActive else { return }
        startListening()
    }

    // MARK: - Conversation Loop

    private func handleUserUtterance(_ text: String) async {
        stopListening()

        // Add user turn to transcript
        currentTranscript.addTurn(role: "user", text: text)

        // Switch to thinking state
        state = .thinking
        amplitude = 0.0

        // Get LLM response
        do {
            let response = try await llmService.generate(prompt: text)

            // Add assistant turn to transcript
            currentTranscript.addTurn(role: "assistant", text: response)

            // Speak the response (state changes via callbacks)
            speechSynthesizer.speak(response)
        } catch {
            errorMessage = "LLM error: \(error.localizedDescription)"
            continueListening()
        }
    }

    // MARK: - Speaking Animation

    private func startSpeakingAnimation() {
        speakingAnimationPhase = 0.0
        speakingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.state == .speaking else { return }
                self.speakingAnimationPhase += 0.1
                // Sine wave amplitude between 0.3 and 0.7
                self.amplitude = 0.5 + 0.2 * Float(sin(self.speakingAnimationPhase))
            }
        }
    }

    private func stopSpeakingAnimation() {
        speakingTimer?.invalidate()
        speakingTimer = nil
        amplitude = 0.0
    }
}
