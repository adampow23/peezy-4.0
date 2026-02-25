//
//  ConfettiView.swift
//  PeezyV1.0
//
//  Confetti particle system for celebrations
//

import SwiftUI

// MARK: - Confetti Particle Model

enum ConfettiShape {
    case circle(diameter: CGFloat)
    case rectangle(width: CGFloat, height: CGFloat)
}

struct ConfettiParticle {
    var position: CGPoint
    var velocity: CGVector
    var rotation: Double          // 2D Rotation (radians)
    var rotationSpeed: Double     // radians per second
    var spin: Double              // 3D Flip axis (radians)
    var spinSpeed: Double         // 3D Flip speed
    var opacity: Double
    var color: Color
    var shape: ConfettiShape
    var wobbleFreq: Double        // Hz
    var wobblePhase: Double       // radian offset
}

// MARK: - Confetti Intensity

/// Controls the particle emission rate. `.high` emits 6–8 particles per batch; `.low` emits 2–3.
enum ConfettiIntensity {
    case low
    case high
}

// MARK: - Particle System State

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

    // Premium "Neon Glass" Palette
    private let colors: [Color] = [
        Color(red: 1.00, green: 0.84, blue: 0.00), // Pure Gold
        Color(red: 0.00, green: 0.94, blue: 1.00), // Electric Cyan
        Color(red: 1.00, green: 0.00, blue: 0.50), // Hot Pink
        Color(red: 0.69, green: 0.00, blue: 1.00), // Neon Purple
        Color(red: 0.00, green: 1.00, blue: 0.66), // Mint Glow
        .white
    ]

    var body: some View {
        TimelineView(.animation(paused: !isActive)) { timeline in
            Canvas { context, size in
                let now = timeline.date
                let elapsed = now.timeIntervalSince(state.startDate)
                let dt = min(now.timeIntervalSince(state.lastFrameDate), 1.0 / 30.0)

                // Emit new particles during first 2 seconds
                if elapsed <= 2.0 && elapsed >= state.nextEmitTime {
                    let batchCount = intensity == .low ? Int.random(in: 3...5) : Int.random(in: 8...12)
                    for _ in 0..<batchCount {
                        state.particles.append(makeParticle(screenSize: size))
                    }
                    // Emitting slightly faster for a denser, premium burst
                    state.nextEmitTime = elapsed + 0.05
                }

                // Fire settling callback once at t=2.2s.
                if elapsed >= 2.2 && !state.settlingFired {
                    state.settlingFired = true
                    DispatchQueue.main.async { onSettling?() }
                }

                // Update physics
                let gravity: Double = 500 // Stronger gravity for the explosive arc
                
                for i in state.particles.indices {
                    var p = state.particles[i]

                    // Apply air resistance (friction) to horizontal movement
                    p.velocity.dx *= 0.98
                    
                    // Gravity
                    p.velocity.dy += gravity * dt

                    // Horizontal flutter (wobble)
                    let wobble = sin(elapsed * p.wobbleFreq + p.wobblePhase) * 25
                    p.position.x += (p.velocity.dx + wobble) * dt
                    p.position.y += p.velocity.dy * dt

                    // Rotations (2D and 3D)
                    p.rotation += p.rotationSpeed * dt
                    p.spin += p.spinSpeed * dt

                    // Fade near bottom
                    if p.position.y > size.height * 0.8 {
                        p.opacity -= dt * 1.5
                    }

                    state.particles[i] = p
                }

                // Remove dead particles (ensure they are falling down before removing off-screen)
                state.particles.removeAll { ($0.position.y > size.height + 50 && $0.velocity.dy > 0) || $0.opacity <= 0 }

                state.lastFrameDate = now

                // Draw particles
                for p in state.particles {
                    var ctx = context
                    
                    // Move to particle position
                    ctx.translateBy(x: p.position.x, y: p.position.y)
                    // Apply 2D Rotation
                    ctx.rotate(by: .radians(p.rotation))
                    // Apply 3D Tumbling Effect (Squishing the Y axis)
                    ctx.scaleBy(x: 1, y: max(0.1, abs(cos(p.spin))))
                    
                    // Set color
                    let fillStyle = GraphicsContext.Shading.color(p.color.opacity(p.opacity))

                    switch p.shape {
                    case .circle(let diameter):
                        let rect = CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter)
                        ctx.fill(Path(ellipseIn: rect), with: fillStyle)

                    case .rectangle(let w, let h):
                        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
                        // Rounded rectangle for a premium, die-cut paper look
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: fillStyle)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            state.reset()
        }
    }

    private func makeParticle(screenSize: CGSize) -> ConfettiParticle {
        let isRect = Bool.random()
        let shape: ConfettiShape = isRect
            ? .rectangle(width: CGFloat.random(in: 8...14), height: CGFloat.random(in: 6...10))
            : .circle(diameter: CGFloat.random(in: 6...9))

        // Dual-Cannon Spawning: Choose left or right corner
        let isLeftCannon = Bool.random()
        
        // Spawn slightly off-screen at the bottom
        let startX: CGFloat = isLeftCannon ? -20 : screenSize.width + 20
        let startY: CGFloat = screenSize.height + 10
        
        // Shoot inwards and upwards
        let velocityX = isLeftCannon ? Double.random(in: 150...600) : Double.random(in: -600...(-150))
        let velocityY = Double.random(in: -1200...(-700))

        return ConfettiParticle(
            position: CGPoint(x: startX, y: startY),
            velocity: CGVector(dx: velocityX, dy: velocityY),
            rotation: Double.random(in: 0...(2 * .pi)),
            rotationSpeed: Double.random(in: -5...5),
            spin: Double.random(in: 0...(2 * .pi)),
            spinSpeed: Double.random(in: -8...8), // Fast 3D tumble
            opacity: 1.0,
            color: colors.randomElement() ?? .white,
            shape: shape,
            wobbleFreq: Double.random(in: 1.5...4.0),
            wobblePhase: Double.random(in: 0...(2 * .pi))
        )
    }
}

// MARK: - Preview

#Preview {
    // Note: TimelineView(.animation) hangs Xcode Canvas previews.
    // Test ConfettiView in the simulator via AssessmentCompleteView.
    ZStack {
        Color(red: 0.05, green: 0.05, blue: 0.1).ignoresSafeArea() // Midnight background
        Text("Run in simulator to preview")
            .foregroundStyle(Color.gray)
    }
}
