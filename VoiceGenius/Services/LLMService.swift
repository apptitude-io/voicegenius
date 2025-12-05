import Foundation

/// Protocol for LLM inference services
protocol LLMService: Sendable {
    func generate(prompt: String) async throws -> String
}

/// Extended protocol for services that support lifecycle management
protocol ManagedLLMService: LLMService {
    /// Unload the model from memory
    func unload() async

    /// Check if the model is ready
    var isReady: Bool { get }
}

/// Factory to create the appropriate LLM service based on configuration
@MainActor
enum LLMFactory {
    /// Create a service using the current settings
    static func create() -> LLMService {
        let settings = SettingsViewModel.shared

        switch settings.backend {
        case .foundation:
            if #available(iOS 26, *), FoundationLLMService.isAvailable {
                return FoundationLLMService(systemPrompt: settings.systemPrompt)
            }
            // Fallback to MLX if Foundation unavailable
            return createMLXService()

        case .mlx:
            return createMLXService()
        }
    }

    /// Create the MLX-based service (respects simulator vs device)
    private static func createMLXService() -> LLMService {
        #if targetEnvironment(simulator)
        return SidecarLLMService()
        #else
        return OnDeviceLLMService()
        #endif
    }

    /// Create a service for a specific backend (for testing/override)
    static func create(backend: LLMBackend) -> LLMService {
        switch backend {
        case .foundation:
            if #available(iOS 26, *), FoundationLLMService.isAvailable {
                return FoundationLLMService()
            }
            return createMLXService()

        case .mlx:
            return createMLXService()
        }
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
