import SwiftUI

/// Overlay view showing model download progress
struct DownloadProgressView: View {
    let state: ModelDownloadState
    let progressText: String
    let isOnCellular: Bool
    let onCancel: () -> Void

    private var progress: Double {
        if case .downloading(let received, let total, _) = state, total > 0 {
            return Double(received) / Double(total)
        }
        return 0
    }

    private var currentFile: String {
        if case .downloading(_, _, let file) = state {
            return file
        }
        return ""
    }

    private var statusText: String {
        switch state {
        case .checkingRequirements:
            return "Checking requirements..."
        case .downloading:
            return "Downloading Model"
        case .validating:
            return "Verifying integrity..."
        case .completed:
            return "Download complete!"
        case .failed(let message):
            return "Error: \(message)"
        default:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Cellular warning
            if isOnCellular && state.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.orange)
                    Text("Using cellular data (~1.7 GB)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.15))
                )
            }

            // Title
            Text(statusText)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if case .downloading = state {
                VStack(spacing: 12) {
                    // Progress bar
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .frame(width: 250)

                    // Percentage and bytes
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.headline)
                            .foregroundColor(.white)

                        Spacer()

                        Text(progressText)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(width: 250)

                    // Current file
                    if !currentFile.isEmpty {
                        Text(currentFile)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 250)
                    }
                }
            } else if case .checkingRequirements = state {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if case .validating = state {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .green))
            }

            // Cancel button
            if state.isActive {
                Button(action: onCancel) {
                    Text("Cancel")
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .stroke(Color.red, lineWidth: 1)
                        )
                }
            }
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.9))
        )
    }
}

/// View shown while checking for model
struct CheckingModelView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)

            Text("Checking model...")
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DownloadProgressView(
            state: .downloading(bytesReceived: 750_000_000, totalBytes: 1_700_000_000, currentFile: "model.safetensors"),
            progressText: "750 / 1700 MB",
            isOnCellular: true,
            onCancel: {}
        )
    }
}
