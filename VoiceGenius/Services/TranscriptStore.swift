import Foundation
import SwiftUI

/// Service for persisting and loading conversation transcripts
@MainActor
@Observable
final class TranscriptStore {
    var transcripts: [Transcript] = []

    private var transcriptsDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("transcripts", isDirectory: true)
    }

    init() {
        createDirectoryIfNeeded()
        loadAllTranscripts()
    }

    private func createDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: transcriptsDirectory.path) {
            try? FileManager.default.createDirectory(at: transcriptsDirectory, withIntermediateDirectories: true)
        }
    }

    func save(_ transcript: Transcript) throws {
        let fileURL = transcriptsDirectory.appendingPathComponent("\(transcript.id.uuidString).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(transcript)
        try data.write(to: fileURL)

        // Update in-memory list
        if let index = transcripts.firstIndex(where: { $0.id == transcript.id }) {
            transcripts[index] = transcript
        } else {
            transcripts.insert(transcript, at: 0)
        }
    }

    func loadAllTranscripts() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: transcriptsDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        transcripts = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Transcript? in
                guard let data = try? Data(contentsOf: url),
                      let transcript = try? decoder.decode(Transcript.self, from: data) else {
                    return nil
                }
                return transcript
            }
            .sorted { $0.date > $1.date }
    }

    func delete(_ transcript: Transcript) throws {
        let fileURL = transcriptsDirectory.appendingPathComponent("\(transcript.id.uuidString).json")
        try FileManager.default.removeItem(at: fileURL)
        transcripts.removeAll { $0.id == transcript.id }
    }

    func transcript(for id: UUID) -> Transcript? {
        transcripts.first { $0.id == id }
    }
}
