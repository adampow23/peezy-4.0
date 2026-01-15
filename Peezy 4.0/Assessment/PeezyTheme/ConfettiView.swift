//
//  ConfettiView.swift
//  PeezyV1.0
//
//  Confetti particle system for celebrations
//

import SwiftUI

// MARK: - Confetti Particle Model

struct ConfettiParticle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGVector
    var rotation: Double
    var rotationSpeed: Double
    var scale: CGFloat
    var opacity: Double
    var color: Color
    var shape: ConfettiShape

    enum ConfettiShape: CaseIterable {
        case circle
        case checkmark
        case star
    }
}

// MARK: - Confetti Intensity

enum ConfettiIntensity {
    case low
    case high

    var particleCount: Int {
        switch self {
        case .low: return 1
        case .high: return 600
        }
    }

    var emissionDuration: Double {
        switch self {
        case .low: return 0.7 // Continuous
        case .high: return 0.8 // Burst
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @Binding var isActive: Bool
    let intensity: ConfettiIntensity

    @State private var particles: [ConfettiParticle] = []
    @State private var timer: Timer?

    private let yellowColor = Color(red: 0.98, green: 0.85, blue: 0.29)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    ParticleView(particle: particle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if isActive {
                    startConfetti(in: geometry.size)
                }
            }
            .onChange(of: isActive) { _, active in
                if active {
                    startConfetti(in: geometry.size)
                } else {
                    stopConfetti()
                }
            }
        }
    }

    private func startConfetti(in size: CGSize) {
        particles.removeAll()

        if intensity == .high {
            // Burst emission
            let emissionCenter = CGPoint(x: size.width / 2, y: size.height / 2)
            for _ in 0..<intensity.particleCount {
                particles.append(createParticle(from: emissionCenter, size: size))
            }

            // Animate particles
            animateParticles(size: size)
        } else {
            // Continuous emission for background ambiance
            timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                if particles.count < 30 {
                    let emissionPoint = CGPoint(x: CGFloat.random(in: 0...size.width), y: -20)
                    particles.append(createParticle(from: emissionPoint, size: size, gentle: true))
                }
                animateParticles(size: size)
            }
        }
    }

    private func stopConfetti() {
        timer?.invalidate()
        timer = nil

        withAnimation(.easeOut(duration: 1.0)) {
            particles.removeAll()
        }
    }

    private func createParticle(from origin: CGPoint, size: CGSize, gentle: Bool = false) -> ConfettiParticle {
        let colors: [Color] = [
            yellowColor,
            .white,
            Color(white: 0.9),
            yellowColor.opacity(0.8)
        ]

        let velocityMagnitude: CGFloat = gentle ? CGFloat.random(in: 50...150) : CGFloat.random(in: 300...600)
        let angle = Double.random(in: gentle ? -Double.pi/6...Double.pi/6 : 0...(2 * .pi))

        return ConfettiParticle(
            position: origin,
            velocity: CGVector(
                dx: cos(angle) * velocityMagnitude,
                dy: gentle ? velocityMagnitude : sin(angle) * velocityMagnitude
            ),
            rotation: Double.random(in: 0...(2 * .pi)),
            rotationSpeed: Double.random(in: -10...10),
            scale: gentle ? CGFloat.random(in: 0.3...0.6) : CGFloat.random(in: 0.5...1.2),
            opacity: 1.0,
            color: colors.randomElement()!,
            shape: ConfettiParticle.ConfettiShape.allCases.randomElement()!
        )
    }

    private func animateParticles(size: CGSize) {
        let updateInterval: TimeInterval = 1/60.0 // 60 FPS
        let gravity: CGFloat = 500 // pixels per second squared

        Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: false) { _ in
            for index in particles.indices {
                var particle = particles[index]

                // Update position
                particle.position.x += particle.velocity.dx * updateInterval
                particle.position.y += particle.velocity.dy * updateInterval

                // Apply gravity
                particle.velocity.dy += gravity * updateInterval

                // Update rotation
                particle.rotation += particle.rotationSpeed * updateInterval

                // Fade out
                if particle.position.y > size.height - 100 {
                    particle.opacity -= 0.02
                }

                particles[index] = particle
            }

            // Remove particles that are off-screen or fully transparent
            particles.removeAll { particle in
                particle.position.y > size.height + 50 || particle.opacity <= 0
            }

            // Continue animation if particles exist
            if !particles.isEmpty && isActive {
                animateParticles(size: size)
            }
        }
    }
}

// MARK: - Particle View

struct ParticleView: View {
    let particle: ConfettiParticle

    var body: some View {
        Group {
            switch particle.shape {
            case .circle:
                Circle()
                    .fill(particle.color)
                    .frame(width: 8, height: 8)

            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(particle.color)

            case .star:
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(particle.color)
            }
        }
        .scaleEffect(particle.scale)
        .rotationEffect(.degrees(particle.rotation * 180 / .pi))
        .opacity(particle.opacity)
        .position(particle.position)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.3)
            .ignoresSafeArea()

        ConfettiView(isActive: .constant(true), intensity: .high)
    }
}
