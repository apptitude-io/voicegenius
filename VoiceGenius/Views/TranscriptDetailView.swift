import SwiftUI

/// View displaying a single conversation transcript
struct TranscriptDetailView: View {
    let transcript: Transcript

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(transcript.turns.enumerated()), id: \.offset) { _, turn in
                    MessageBubble(turn: turn)
                }
            }
            .padding()
        }
        .navigationTitle(dateFormatter.string(from: transcript.date))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
}

struct MessageBubble: View {
    let turn: Transcript.Turn

    private var isUser: Bool {
        turn.role == "user"
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(isUser ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(turn.text)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.blue : Color(.systemGray5))
                    )
                    .foregroundColor(isUser ? .white : .primary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

#Preview {
    NavigationStack {
        TranscriptDetailView(transcript: Transcript(
            turns: [
                .init(role: "user", text: "Hello, how are you?", timestamp: Date().timeIntervalSince1970),
                .init(role: "assistant", text: "I'm doing well, thank you for asking! How can I help you today?", timestamp: Date().timeIntervalSince1970 + 1)
            ]
        ))
    }
}
