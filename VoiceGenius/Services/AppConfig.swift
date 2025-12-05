import Foundation

/// Central configuration loaded from config.json
struct AppConfig: Codable {
    let model: String
    let maxTokens: Int
    let systemPrompt: String

    /// Model name without the repo prefix (e.g., "Qwen2.5-3B-Instruct-4bit")
    var modelName: String {
        model.components(separatedBy: "/").last ?? model
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case systemPrompt = "system_prompt"
    }

    /// Shared instance loaded from bundle
    static let shared: AppConfig = {
        guard let url = Bundle.main.url(forResource: "config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            // Fallback defaults
            return AppConfig(
                model: "mlx-community/Qwen2.5-3B-Instruct-4bit",
                maxTokens: 256,
                systemPrompt: ""
            )
        }
        return config
    }()
}
