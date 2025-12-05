import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// LLM service using Apple's Foundation Models (Apple Intelligence)
/// Available on iOS 26+ devices with Apple Intelligence capability
final class FoundationLLMService: LLMService, @unchecked Sendable {

    private let systemPrompt: String

    #if canImport(FoundationModels)
    // Use Any type to avoid @available issues with stored properties
    private var _session: Any?

    @available(iOS 26, *)
    private var session: LanguageModelSession? {
        get { _session as? LanguageModelSession }
        set { _session = newValue }
    }
    #endif

    init(systemPrompt: String = "") {
        // Capture system prompt at init time to avoid actor isolation issues
        if systemPrompt.isEmpty {
            // We'll fetch the system prompt lazily when needed
            self.systemPrompt = ""
        } else {
            self.systemPrompt = systemPrompt
        }
    }

    /// Check if Foundation Models are available on this device
    @MainActor
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false // Apple Intelligence requires physical device with Neural Engine
        #elseif canImport(FoundationModels)
        if #available(iOS 26, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
        #else
        return false
        #endif
    }

    func generate(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else {
            throw LLMError.generationFailed("Foundation Models require iOS 26 or later")
        }

        // Get system prompt from settings if not provided at init
        let effectiveSystemPrompt: String
        if systemPrompt.isEmpty {
            effectiveSystemPrompt = await MainActor.run { SettingsViewModel.shared.systemPrompt }
        } else {
            effectiveSystemPrompt = systemPrompt
        }

        // Create session if needed
        if session == nil {
            do {
                if effectiveSystemPrompt.isEmpty {
                    session = LanguageModelSession()
                } else {
                    session = LanguageModelSession(instructions: effectiveSystemPrompt)
                }
            } catch {
                throw LLMError.generationFailed("Failed to create Foundation session: \(error.localizedDescription)")
            }
        }

        guard let session = session else {
            throw LLMError.modelNotLoaded
        }

        do {
            let response = try await session.respond(to: prompt)
            // Response is LanguageModelSession.Response<String>, extract the content
            return response.content
        } catch {
            throw LLMError.generationFailed("Foundation generation failed: \(error.localizedDescription)")
        }

        #else
        throw LLMError.generationFailed("Foundation Models not available on this platform")
        #endif
    }

    /// Reset the session (for hot-swapping or clearing context)
    func resetSession() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            session = nil
        }
        #endif
    }
}
