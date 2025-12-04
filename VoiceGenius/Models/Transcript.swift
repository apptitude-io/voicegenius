import Foundation

struct Transcript: Codable, Identifiable {
    let id: UUID
    let date: Date
    var turns: [Turn]

    struct Turn: Codable {
        let role: String  // "user" | "assistant"
        let text: String
        let timestamp: TimeInterval
    }

    init(id: UUID = UUID(), date: Date = Date(), turns: [Turn] = []) {
        self.id = id
        self.date = date
        self.turns = turns
    }

    mutating func addTurn(role: String, text: String) {
        let turn = Turn(
            role: role,
            text: text,
            timestamp: Date().timeIntervalSince1970
        )
        turns.append(turn)
    }
}
