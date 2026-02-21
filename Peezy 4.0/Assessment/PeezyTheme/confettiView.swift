//
//  ConfettiView.swift
//  PeezyV1.0
//
//  Confetti particle system for celebrations
//

import SwiftUI
import Observation

// MARK: - Confetti Particle Model

enum ConfettiShape {
    case circle(diameter: CGFloat)
    case rectangle(width: CGFloat, height: CGFloat)
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var rotation: Double          // radians
    var rotationSpeed: Double     // radians per second
    var opacity: Double
    var color: Color
    var shape: ConfettiShape
    var wobbleFreq: Double        // Hz — unique per particle
    var wobblePhase: Double       // radian offset — unique per particle
}

// MARK: - Confetti Intensity

enum ConfettiIntensity {
    case low
    case high
}

// MARK: - Particle System State (class so Canvas can mutate it)

@Observable
private final class ParticleSystemState {
    var particles: [ConfettiParticle] = []
    var startDate: Date = Date()
    var lastFrameDate: Date = Date()
    var settlingFired: Bool = false
    var nextEmitTime: Double = 0

    func reset() {
        particles = []
        startDate = Date()
        lastFrameDate = Date()
        settlingFired = false
        nextEmitTime = 0
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @Binding var isActive: Bool
    let intensity: ConfettiIntensity
    var onSettling: (() -> Void)? = nil

    @State private var state = ParticleSystemState()

    private let colors: [Color] = [
        Color(red: 0.98, green: 0.85, blue: 0.29), // gold
        .white,
        Color(red: 0.45, green: 0.78, blue: 0.98), // light blue
        Color(red: 0.98, green: 0.50, blue: 0.45), // coral
        Color(red: 0.45, green: 0.88, blue: 0.70), // mint
        Color(red: 0.75, green: 0.55, blue: 0.95)  // soft purple
    ]

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date
                    let elapsed = now.timeIntervalSince(state.startDate)
                    let dt = now.timeIntervalSince(state.lastFrameDate)

                    // Emit new particles during first 2 seconds
                    if elapsed <= 2.0 && elapsed >= state.nextEmitTime {
                        let batchCount = Int.random(in: 6...8)
                        for _ in 0..<batchCount {
                            state.particles.append(makeParticle(screenWidth: size.width))
                        }
                        state.nextEmitTime = elapsed + 0.08
                    }

                    // Fire settling callback once at t=2.2s
                    if elapsed >= 2.2 && !state.settlingFired {
                        state.settlingFired = true
                        DispatchQueue.main.async { onSettling?() }
                    }

                    // Update physics
                    let gravity: Double = 380
                    for i in state.particles.indices {
                        var p = state.particles[i]

                        // Gravity
                        p.velocity.dy += gravity * dt

                        // Horizontal wobble
                        let wobble = sin(elapsed * p.wobbleFreq + p.wobblePhase) * 18
                        p.position.x += (p.velocity.dx + wobble) * dt
                        p.position.y += p.velocity.dy * dt

                        // Rotation
                        p.rotation += p.rotationSpeed * dt

                        // Fade near bottom
                        if p.position.y > size.height * 0.75 {
                            p.opacity -= dt * 1.8
                        }

                        state.particles[i] = p
                    }

                    // Remove dead particles
                    state.particles.removeAll { $0.position.y > size.height + 20 || $0.opacity <= 0 }

                    state.lastFrameDate = now

                    // Draw particles
                    for p in state.particles {
                        switch p.shape {
                        case .circle(let diameter):
                            let rect = CGRect(
                                x: p.position.x - diameter / 2,
                                y: p.position.y - diameter / 2,
                                width: diameter,
                                height: diameter
                            )
                            context.fill(Path(ellipseIn: rect), with: .color(p.color.opacity(p.opacity)))

                        case .rectangle(let w, let h):
                            var ctx = context
                            ctx.translateBy(x: p.position.x, y: p.position.y)
                            ctx.rotate(by: .radians(p.rotation))
                            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                            ctx.fill(Path(rect), with: .color(p.color.opacity(p.opacity)))
                        }
                    }
                }
            }
            .onAppear {
                state.reset()
            }
        }
    }

    private func makeParticle(screenWidth: CGFloat) -> ConfettiParticle {
        let isRect = Bool.random()
        let shape: ConfettiShape = isRect
            ? .rectangle(
                width: CGFloat.random(in: 6...12),
                height: CGFloat.random(in: 4...8)
              )
            : .circle(diameter: CGFloat.random(in: 4...6))

        let dxMag = Double.random(in: 30...80)
        let dx = Bool.random() ? dxMag : -dxMag

        return ConfettiParticle(
            position: CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: -10
            ),
            velocity: CGVector(
                dx: dx,
                dy: Double.random(in: 180...320)
            ),
            rotation: Double.random(in: 0...(2 * .pi)),
            rotationSpeed: Double.random(in: -6...6),
            opacity: 1.0,
            color: colors.randomElement()!,
            shape: shape,
            wobbleFreq: Double.random(in: 1.5...3.5),
            wobblePhase: Double.random(in: 0...(2 * .pi))
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ConfettiView(isActive: .constant(true), intensity: .high)
    }
}
