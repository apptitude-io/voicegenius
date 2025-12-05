import Foundation

/// The LLM backend provider
enum LLMBackend: String, Codable, CaseIterable {
    case mlx        // Custom HuggingFace models via MLX Swift
    case foundation // Apple Intelligence (iOS 26+)

    var displayName: String {
        switch self {
        case .mlx: return "HuggingFace"
        case .foundation: return "Apple Intelligence"
        }
    }

    var description: String {
        switch self {
        case .mlx:
            return "Run open source models locally using MLX. Requires model download."
        case .foundation:
            return "Use Apple's built-in AI models. No download required."
        }
    }

    /// Check if this backend is available on the current device
    var isAvailable: Bool {
        switch self {
        case .mlx:
            return true // Via sidecar (Simulator) or MLX Swift (Device)
        case .foundation:
            #if targetEnvironment(simulator)
            return false // Apple Intelligence requires physical device
            #else
            if #available(iOS 26, *) {
                return true
            }
            return false
            #endif
        }
    }
}

/// Preset configurations for MLX models
struct ModelPreset: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let repoId: String
    let description: String
    let sizeDescription: String

    static let balanced = ModelPreset(
        id: "balanced",
        name: "Balanced",
        repoId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
        description: "Good balance of speed and quality",
        sizeDescription: "~2GB"
    )

    static let efficient = ModelPreset(
        id: "efficient",
        name: "Efficient",
        repoId: "mlx-community/Llama-3.2-1B-Instruct-4bit",
        description: "Faster responses, lower memory usage",
        sizeDescription: "~700MB"
    )

    static let allPresets: [ModelPreset] = [.balanced, .efficient]

    static func preset(for id: String) -> ModelPreset? {
        allPresets.first { $0.id == id }
    }

    static func preset(forRepoId repoId: String) -> ModelPreset? {
        allPresets.first { $0.repoId == repoId }
    }
}
