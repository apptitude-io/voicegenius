import Foundation

#if !targetEnvironment(simulator)
import MLXLLM
import MLX
import MLXLMCommon
#endif

/// LLM service that runs inference on-device using MLX Swift
final class OnDeviceLLMService: ManagedLLMService, @unchecked Sendable {
    #if !targetEnvironment(simulator)
    private var model: LLMModel?
    private var tokenizer: Tokenizer?
    #endif

    private var modelDirectory: URL {
        ModelDownloader.modelDirectory
    }

    init() {}

    func loadModel() async throws {
        #if !targetEnvironment(simulator)
        guard FileManager.default.fileExists(atPath: modelDirectory.path) else {
            throw LLMError.modelNotLoaded
        }

        // Load the model from the local directory
        let configuration = ModelConfiguration(directory: modelDirectory)
        let (loadedModel, loadedTokenizer) = try await MLXLLM.load(configuration: configuration)
        self.model = loadedModel
        self.tokenizer = loadedTokenizer
        #endif
    }

    func generate(prompt: String) async throws -> String {
        #if targetEnvironment(simulator)
        throw LLMError.modelNotLoaded
        #else
        guard let model = model, let tokenizer = tokenizer else {
            throw LLMError.modelNotLoaded
        }

        // Get settings from SettingsViewModel
        let settings = await MainActor.run { SettingsViewModel.shared }
        let systemPrompt = await MainActor.run { settings.systemPrompt }
        let maxTokens = await MainActor.run { settings.maxTokens }

        // Build messages with optional system prompt
        var messages: [[String: String]] = []
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        // Apply chat template
        let formattedPrompt = try tokenizer.applyChatTemplate(messages: messages)

        // Generate response
        let parameters = GenerateParameters(maxTokens: maxTokens)

        let result = try await model.generate(
            prompt: formattedPrompt,
            parameters: parameters
        ) { _ in
            return .more
        }

        return result.output
        #endif
    }

    /// Unload the model from memory to free ~2GB RAM
    func unload() async {
        #if !targetEnvironment(simulator)
        model = nil
        tokenizer = nil

        // Force MLX to release cached memory
        MLX.GPU.clearCache()
        #endif
    }

    var isReady: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return model != nil && tokenizer != nil
        #endif
    }

    // Legacy alias for compatibility
    var isModelLoaded: Bool { isReady }
}
