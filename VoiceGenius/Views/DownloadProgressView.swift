import SwiftUI

/// Overlay view showing model download progress
struct DownloadProgressView: View {
    let progress: Double
    let currentFile: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Downloading Model")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(width: 250)

                Text("\(Int(progress * 100))%")
                    .font(.headline)
                    .foregroundColor(.white)

                if !currentFile.isEmpty {
                    Text(currentFile)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 250)
                }
            }

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
            progress: 0.45,
            currentFile: "model.safetensors",
            onCancel: {}
        )
    }
}
