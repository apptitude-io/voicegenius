import SwiftUI

/// View displaying list of saved conversation transcripts
struct TranscriptHistoryView: View {
    @Bindable var store: TranscriptStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if store.transcripts.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your conversation history will appear here")
                    )
                } else {
                    ForEach(store.transcripts) { transcript in
                        NavigationLink(destination: TranscriptDetailView(transcript: transcript)) {
                            TranscriptRow(transcript: transcript)
                        }
                    }
                    .onDelete(perform: deleteTranscripts)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func deleteTranscripts(at offsets: IndexSet) {
        for index in offsets {
            let transcript = store.transcripts[index]
            try? store.delete(transcript)
        }
    }
}

struct TranscriptRow: View {
    let transcript: Transcript

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var preview: String {
        transcript.turns.first?.text ?? "Empty conversation"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateFormatter.string(from: transcript.date))
                .font(.headline)

            Text(preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text("\(transcript.turns.count) messages")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TranscriptHistoryView(store: TranscriptStore())
}
