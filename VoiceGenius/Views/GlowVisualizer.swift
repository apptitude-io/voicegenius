import SwiftUI

/// Animated breathing circle visualizer that reacts to audio amplitude
struct GlowVisualizer: View {
    let amplitude: Float
    let state: ConversationState

    private let baseRadius: CGFloat = 80
    private let maxExpansion: CGFloat = 40

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                // Calculate radius based on state and amplitude
                let radius = calculateRadius(phase: phase)

                // Draw multiple layers for glow effect
                for i in stride(from: 5, through: 1, by: -1) {
                    let layerRadius = radius + CGFloat(i) * 15
                    let opacity = 0.15 / Double(i)

                    let circle = Path(ellipseIn: CGRect(
                        x: center.x - layerRadius,
                        y: center.y - layerRadius,
                        width: layerRadius * 2,
                        height: layerRadius * 2
                    ))

                    context.fill(circle, with: .color(state.glowColor.opacity(opacity)))
                }

                // Draw main circle
                let mainCircle = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))

                context.fill(mainCircle, with: .color(state.glowColor.opacity(0.8)))

                // Inner bright core
                let coreRadius = radius * 0.6
                let coreCircle = Path(ellipseIn: CGRect(
                    x: center.x - coreRadius,
                    y: center.y - coreRadius,
                    width: coreRadius * 2,
                    height: coreRadius * 2
                ))

                context.fill(coreCircle, with: .color(.white.opacity(0.3)))
            }
        }
        .frame(width: 300, height: 300)
    }

    private func calculateRadius(phase: Double) -> CGFloat {
        switch state {
        case .idle:
            // Gentle breathing animation
            let breathe = sin(phase * 0.5) * 0.1 + 0.9
            return baseRadius * breathe

        case .listening, .speaking:
            // React to amplitude
            let amplitudeEffect = CGFloat(amplitude) * maxExpansion
            return baseRadius + amplitudeEffect

        case .thinking:
            // Slow sine-wave pulse
            let pulse = sin(phase * 2) * 0.15 + 1.0
            return baseRadius * pulse
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        GlowVisualizer(amplitude: 0.5, state: .listening)
    }
}
