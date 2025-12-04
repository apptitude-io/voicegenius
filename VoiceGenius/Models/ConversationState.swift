import SwiftUI

enum ConversationState {
    case idle
    case listening   // Red glow - user speaking
    case thinking    // White glow - processing
    case speaking    // Blue glow - AI speaking

    var glowColor: Color {
        switch self {
        case .idle:
            return .gray
        case .listening:
            return .red
        case .thinking:
            return .white
        case .speaking:
            return .blue
        }
    }
}
