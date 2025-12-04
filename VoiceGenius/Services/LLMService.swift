import Foundation

/// Protocol for LLM inference services
protocol LLMService: Sendable {
    func generate(prompt: String) async throws -> String
}

/// Factory to create the appropriate LLM service based on target
enum LLMFactory {
    static func create() -> LLMService {
        #if targetEnvironment(simulator)
        return SidecarLLMService()
        #else
        return OnDeviceLLMService()
        #endif
    }
}

/// Errors that can occur during LLM operations
enum LLMError: Error, LocalizedError {
    case networkError(Error)
    case invalidResponse
    case modelNotLoaded
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from LLM service"
        case .modelNotLoaded:
            return "Model is not loaded"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}
