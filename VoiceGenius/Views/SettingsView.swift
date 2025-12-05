import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SettingsViewModel.shared
    @State private var showingResetConfirmation = false

    /// Callback when backend/model changes (for hot-swap)
    var onConfigurationChanged: (() -> Void)?

    /// Model download state from parent
    var modelDownloader: ModelDownloader?

    var body: some View {
        NavigationStack {
            Form {
                backendSection
                if settings.backend == .mlx {
                    mlxConfigSection
                }
                systemPromptSection
                advancedSection
                resetSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Reset to Defaults",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    settings.resetToDefaults()
                    settings.notifyConfigurationChanged()
                    onConfigurationChanged?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all settings to their default values.")
            }
        }
    }

    // MARK: - Backend Section

    /// Available backends (filtered by device capability)
    private var availableBackends: [LLMBackend] {
        LLMBackend.allCases.filter { $0.isAvailable }
    }

    private var backendSection: some View {
        Section {
            // Only show picker if multiple backends available
            if availableBackends.count > 1 {
                Picker("Backend", selection: $settings.backend) {
                    ForEach(availableBackends, id: \.self) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!canSwitchBackend)
                .onChange(of: settings.backend) { _, newValue in
                    settings.notifyConfigurationChanged()
                    onConfigurationChanged?()
                }
            }
        } header: {
            Text("LLM Backend")
        } footer: {
            Text(settings.backend.description)
        }
    }

    // MARK: - MLX Config Section

    private var mlxConfigSection: some View {
        Section {
            ForEach(ModelPreset.allPresets) { preset in
                modelPresetRow(preset)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Larger models provide better responses but use more memory and storage.")
        }
    }

    private func modelPresetRow(_ preset: ModelPreset) -> some View {
        let isSelected = settings.selectedPreset.id == preset.id
        let downloadStatus = modelDownloadStatus(for: preset)

        return Button {
            if settings.selectedPreset.id != preset.id {
                settings.selectedPreset = preset
                settings.notifyConfigurationChanged()
                onConfigurationChanged?()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(preset.name)
                            .fontWeight(isSelected ? .semibold : .regular)
                        Text(preset.sizeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                downloadStatusView(downloadStatus)

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private enum ModelDownloadStatus {
        case downloaded
        case notDownloaded
        case downloading(progress: Double)
    }

    private func modelDownloadStatus(for preset: ModelPreset) -> ModelDownloadStatus {
        // Check if this preset's model is downloaded
        let modelDir = ModelDownloader.modelDirectory
        let configFile = modelDir.appendingPathComponent("config.json")

        // For now, we only track if *any* model is downloaded
        // A more robust implementation would track per-model
        if FileManager.default.fileExists(atPath: configFile.path) {
            // Check if it's the current model by comparing to settings
            if settings.selectedPreset.id == preset.id {
                if let state = modelDownloader?.state, state.isActive {
                    return .downloading(progress: modelDownloader?.downloadProgress ?? 0)
                }
                return .downloaded
            }
        }

        if let downloader = modelDownloader,
           settings.selectedPreset.id == preset.id,
           downloader.state.isActive {
            return .downloading(progress: downloader.downloadProgress)
        }

        // For simplicity, show not downloaded for non-selected presets
        // that aren't the current downloaded model
        return settings.selectedPreset.id == preset.id ? .downloaded : .notDownloaded
    }

    @ViewBuilder
    private func downloadStatusView(_ status: ModelDownloadStatus) -> some View {
        switch status {
        case .downloaded:
            Text("Downloaded")
                .font(.caption)
                .foregroundStyle(.green)
        case .notDownloaded:
            Text("Tap to select")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - System Prompt Section

    private var systemPromptSection: some View {
        Section {
            TextEditor(text: $settings.systemPrompt)
                .frame(minHeight: 100)
                .font(.body)
        } header: {
            Text("System Prompt")
        } footer: {
            Text("Customize the AI's persona and behavior.")
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        Section {
            Stepper(value: $settings.maxTokens, in: 64...1024, step: 64) {
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(settings.maxTokens)")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Maximum number of tokens the AI can generate per response.")
        }
    }

    // MARK: - Reset Section

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults", role: .destructive) {
                showingResetConfirmation = true
            }
            .disabled(!settings.hasCustomSettings)
        }
    }

    // MARK: - Helpers

    private var canSwitchBackend: Bool {
        // Don't allow switching while downloading
        if let downloader = modelDownloader, downloader.state.isActive {
            return false
        }
        return true
    }
}

#Preview {
    SettingsView()
}
