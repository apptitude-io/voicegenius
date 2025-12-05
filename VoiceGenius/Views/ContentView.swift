import SwiftUI

/// Main view composing all UI components
struct ContentView: View {
    @State private var viewModel = ConversationViewModel()
    @State private var showingHistory = false
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Main content
            VStack {
                // Top bar with settings and history
                HStack {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                    .disabled(viewModel.isSessionActive)

                    Spacer()

                    Button(action: { showingHistory = true }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                }

                Spacer()

                // Glow visualizer
                GlowVisualizer(
                    amplitude: viewModel.amplitude,
                    state: viewModel.state
                )

                // State indicator
                Text(stateText)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.top, 20)

                Spacer()

                // End session button
                EndSessionButton(
                    isSessionActive: viewModel.isSessionActive,
                    onStart: {
                        Task {
                            await viewModel.startSession()
                        }
                    },
                    onEnd: {
                        viewModel.endSession()
                    }
                )
            }

            // Error message
            if let error = viewModel.errorMessage {
                VStack {
                    Spacer()
                    ErrorBanner(message: error) {
                        viewModel.errorMessage = nil
                    }
                    .padding(.bottom, 120)
                }
            }

            // Loading/Download overlays
            if viewModel.isCheckingModel || viewModel.isSwitchingModel {
                Color.black.opacity(0.8).ignoresSafeArea()
                CheckingModelView(
                    message: viewModel.isSwitchingModel ? "Switching model..." : nil
                )
            } else if viewModel.isDownloading {
                Color.black.opacity(0.8).ignoresSafeArea()
                DownloadProgressView(
                    state: viewModel.downloadState,
                    progressText: viewModel.downloadProgressText,
                    isOnCellular: viewModel.isOnCellular,
                    onCancel: {
                        viewModel.cancelDownload()
                    }
                )
            }
        }
        .sheet(isPresented: $showingHistory) {
            TranscriptHistoryView(store: viewModel.transcriptStore)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                onConfigurationChanged: {
                    Task {
                        await viewModel.reinitializeLLMService()
                    }
                },
                modelDownloader: viewModel.modelDownloader
            )
        }
        .task {
            await viewModel.checkModelAndInitialize()
        }
    }

    private var stateText: String {
        switch viewModel.state {
        case .idle:
            if let model = viewModel.modelName {
                return "Loaded \(model)."
            }
            return "Welcome."
        case .listening:
            return "Listening..."
        case .thinking:
            return "Thinking..."
        case .speaking:
            return "Speaking..."
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.8))
        )
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
