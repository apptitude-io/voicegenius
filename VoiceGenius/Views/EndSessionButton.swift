import SwiftUI

/// Button to end the current conversation session
struct EndSessionButton: View {
    let isSessionActive: Bool
    let onStart: () -> Void
    let onEnd: () -> Void

    var body: some View {
        Button(action: {
            if isSessionActive {
                onEnd()
            } else {
                onStart()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: isSessionActive ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 24))
                Text(isSessionActive ? "End Session" : "Start Session")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(isSessionActive ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
            )
        }
        .padding(.bottom, 50)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            EndSessionButton(isSessionActive: false, onStart: {}, onEnd: {})
            EndSessionButton(isSessionActive: true, onStart: {}, onEnd: {})
        }
    }
}
