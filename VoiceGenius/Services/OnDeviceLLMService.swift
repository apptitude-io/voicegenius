import Foundation

#if !targetEnvironment(simulator)
import MLXLLM
import MLX
import MLXLMCommon
#endif

/// LLM service that runs inference on-device using MLX Swift
final class OnDeviceLLMService: LLMService, @unchecked Sendable {
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

        // Build messages with optional system prompt
        var messages: [[String: String]] = []
        let systemPrompt = AppConfig.shared.systemPrompt
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        // Apply chat template
        let formattedPrompt = try tokenizer.applyChatTemplate(messages: messages)

        // Generate response
        let parameters = GenerateParameters(maxTokens: AppConfig.shared.maxTokens)

        let result = try await model.generate(
            prompt: formattedPrompt,
            parameters: parameters
        ) { _ in
            return .more
        }

        return result.output
        #endif
    }

    var isModelLoaded: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return model != nil && tokenizer != nil
        #endif
    }
}
