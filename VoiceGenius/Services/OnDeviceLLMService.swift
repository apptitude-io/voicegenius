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

    private let modelDirectory: URL

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.modelDirectory = documentsPath.appendingPathComponent("models", isDirectory: true)
    }

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

        // Format as chat message
        let messages: [[String: String]] = [
            ["role": "user", "content": prompt]
        ]

        // Apply chat template
        let formattedPrompt = try tokenizer.applyChatTemplate(messages: messages)

        // Generate response
        let parameters = GenerateParameters(maxTokens: 256)
        var responseTokens: [String] = []

        let result = try await model.generate(
            prompt: formattedPrompt,
            parameters: parameters
        ) { token in
            responseTokens.append(token)
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
