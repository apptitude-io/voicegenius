import Foundation
import SwiftUI

/// Keys for UserDefaults storage
private enum SettingsKey {
    static let backend = "settings.backend"
    static let modelPresetId = "settings.modelPresetId"
    static let systemPrompt = "settings.systemPrompt"
    static let maxTokens = "settings.maxTokens"
}

/// Default values for settings
enum SettingsDefaults {
    static let maxTokens = 256
    static let systemPrompt = """
        You are VoiceGenius, a voice assistant specializing in health insurance questions. 
        You make the confusing world of deductibles, copays, and coverage limits feel less 
        like reading ancient tax scrolls.\n\n
        ## Personality\n
        - Warm, witty, and refreshingly human\n
        - Brief and punchy—1-3 sentences max unless the user asks for detail\n
        - Use light humor to defuse insurance anxiety, but never at the user's expense\n
        - Speak like a smart friend who happens to know insurance, not a corporate FAQ bot\n\n
        ## Guidelines\n
        - Lead with the answer, then explain if needed\n
        - Use plain English. Translate jargon immediately (e.g., \"That's your deductible—the amount you pay before insurance kicks in\")\n
        - If you're unsure or the question requires policy-specific details, say so and suggest they check their plan documents or call their insurer\n
        - Never guess on coverage amounts, specific benefits, or claim outcomes\n
        - For medical emergencies, immediately direct them to call 911 or their doctor\n\n## Off-limits\n
        - Do not provide medical advice, diagnoses, or treatment recommendations\n- Do not make promises about what will or won't be covered\
        - Do not handle PHI or attempt to access accounts\n\n## Tone Examples\n
        - ✅ \"Preventive care is usually covered 100%—that's the one time insurance actually wants you to go to the doctor.\"\n
        - ✅ \"Out-of-pocket max hit? Congrats, your insurance finally earns its keep for the rest of the year.\"\n
        - ❌ Long paragraphs explaining the history of HMOs
        """
}

/// Observable settings manager with UserDefaults persistence
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Published Properties

    var backend: LLMBackend {
        didSet { save() }
    }

    var selectedPreset: ModelPreset {
        didSet { save() }
    }

    var systemPrompt: String {
        didSet { save() }
    }

    var maxTokens: Int {
        didSet { save() }
    }

    // MARK: - Computed Properties

    /// The currently selected model repo ID (for MLX backend)
    var currentModelRepoId: String {
        selectedPreset.repoId
    }

    /// Whether the current configuration has unsaved changes from defaults
    var hasCustomSettings: Bool {
        backend != .mlx ||
        selectedPreset.id != ModelPreset.balanced.id ||
        systemPrompt != SettingsDefaults.systemPrompt ||
        maxTokens != SettingsDefaults.maxTokens
    }

    /// Whether Foundation models are available on this device
    var isFoundationAvailable: Bool {
        LLMBackend.foundation.isAvailable
    }

    // MARK: - Singleton

    static let shared = SettingsViewModel()

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard

        // Load backend preference
        if let backendRaw = defaults.string(forKey: SettingsKey.backend),
           let savedBackend = LLMBackend(rawValue: backendRaw) {
            self.backend = savedBackend
        } else {
            self.backend = .mlx
        }

        // Load model preset
        if let presetId = defaults.string(forKey: SettingsKey.modelPresetId),
           let preset = ModelPreset.preset(for: presetId) {
            self.selectedPreset = preset
        } else {
            self.selectedPreset = .balanced
        }

        // Load system prompt
        if let savedPrompt = defaults.string(forKey: SettingsKey.systemPrompt) {
            self.systemPrompt = savedPrompt
        } else {
            self.systemPrompt = SettingsDefaults.systemPrompt
        }

        // Load max tokens
        let savedTokens = defaults.integer(forKey: SettingsKey.maxTokens)
        self.maxTokens = savedTokens > 0 ? savedTokens : SettingsDefaults.maxTokens
    }

    // MARK: - Actions

    /// Reset all settings to defaults
    func resetToDefaults() {
        backend = .mlx
        selectedPreset = .balanced
        systemPrompt = SettingsDefaults.systemPrompt
        maxTokens = SettingsDefaults.maxTokens
    }

    /// Save current settings to UserDefaults
    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(backend.rawValue, forKey: SettingsKey.backend)
        defaults.set(selectedPreset.id, forKey: SettingsKey.modelPresetId)
        defaults.set(systemPrompt, forKey: SettingsKey.systemPrompt)
        defaults.set(maxTokens, forKey: SettingsKey.maxTokens)
    }
}

// MARK: - Notification for Model Changes

extension Notification.Name {
    /// Posted when the LLM backend or model selection changes
    static let llmConfigurationDidChange = Notification.Name("llmConfigurationDidChange")
}

extension SettingsViewModel {
    /// Call this after changing backend or model to notify listeners
    func notifyConfigurationChanged() {
        NotificationCenter.default.post(name: .llmConfigurationDidChange, object: nil)
    }
}
