# Confetti Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the center-burst icon-based confetti with a top-down paper confetti shower using TimelineView+Canvas, then choreograph the summary text to fade in after the confetti settles.

**Architecture:** ConfettiView is fully rewritten to use `TimelineView(.animation)` driving a `Canvas` renderer. Particle physics (position, velocity, rotation, opacity) live in a `@State` array updated per frame. Emission runs for 2 seconds from the top edge; at t=2.2s an `onSettling` closure is called. AssessmentCompleteView passes that closure to fade in `summaryOpacity`.

**Tech Stack:** SwiftUI (`TimelineView`, `Canvas`, `GraphicsContext`), Swift 5.9+, iOS 17+

---

### Task 1: Rewrite ConfettiView.swift

**Files:**
- Modify: `Peezy 4.0/Assessment/PeezyTheme/ConfettiView.swift`

**Step 1: Read the current file to confirm starting state**

Read `Peezy 4.0/Assessment/PeezyTheme/ConfettiView.swift` — confirm it has `ConfettiShape.checkmark`, `ConfettiShape.star`, center-burst emission, and Timer-based physics loop.

**Step 2: Replace the entire file contents**

Replace with the following complete implementation:

```swift
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

// MARK: - Confetti View

struct ConfettiView: View {
    @Binding var isActive: Bool
    let intensity: ConfettiIntensity
    var onSettling: (() -> Void)? = nil

    @State private var particles: [ConfettiParticle] = []
    @State private var startDate: Date = Date()
    @State private var lastFrameDate: Date = Date()
    @State private var emissionComplete: Bool = false
    @State private var settlingFired: Bool = false
    @State private var nextEmitTime: Double = 0

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
                    let elapsed = now.timeIntervalSince(startDate)
                    let dt = now.timeIntervalSince(lastFrameDate)

                    // Emit new particles during first 2 seconds
                    if elapsed <= 2.0 && elapsed >= nextEmitTime {
                        let batchCount = Int.random(in: 6...8)
                        for _ in 0..<batchCount {
                            particles.append(makeParticle(screenWidth: size.width))
                        }
                        nextEmitTime = elapsed + 0.08
                    }

                    // Fire settling callback once at t=2.2s
                    if elapsed >= 2.2 && !settlingFired {
                        settlingFired = true
                        DispatchQueue.main.async { onSettling?() }
                    }

                    // Update physics
                    let gravity: Double = 380
                    for i in particles.indices {
                        var p = particles[i]

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

                        particles[i] = p
                    }

                    // Remove dead particles
                    particles.removeAll { $0.position.y > size.height + 20 || $0.opacity <= 0 }

                    lastFrameDate = now

                    // Draw particles
                    for p in particles {
                        var resolvedColor = context.resolve(p.color.opacity(p.opacity))

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

                        _ = resolvedColor // silence unused warning
                    }
                }
            }
            .onAppear {
                startDate = Date()
                lastFrameDate = Date()
                particles = []
                emissionComplete = false
                settlingFired = false
                nextEmitTime = 0
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

        return ConfettiParticle(
            position: CGPoint(
                x: CGFloat.random(in: 0...screenWidth),
                y: -10
            ),
            velocity: CGVector(
                dx: Double.random(in: -80...80),
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
```

**Step 3: Build to catch compile errors**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`. Fix any compile errors before continuing.

**Step 4: Commit**

```bash
git add "Peezy 4.0/Assessment/PeezyTheme/ConfettiView.swift"
git commit -m "feat: rewrite ConfettiView with TimelineView+Canvas top-down shower"
```

---

### Task 2: Update AssessmentCompleteView to use onSettling callback

**Files:**
- Modify: `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AsessmentCompleteView.swift`

**Step 1: Read the current file to confirm starting state**

Read `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AsessmentCompleteView.swift` — confirm:
- `revealSummary()` sets `showConfetti = true`, immediately fades in `summaryOpacity` with `.delay(0.3)`
- A `DispatchQueue.main.asyncAfter(deadline: .now() + 4.0)` timer stops confetti
- `ConfettiView(isActive: $showConfetti, intensity: .high)` call site has no `onSettling`

**Step 2: Update `revealSummary()` — remove the simultaneous text fade and confetti stop timer**

Find:
```swift
    private func revealSummary() {
        showConfetti = true

        withAnimation(.easeInOut(duration: 0.5)) {
            stage = .summary
        }
        withAnimation(.easeIn(duration: 0.6).delay(0.3)) {
            summaryOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeOut(duration: 1.0)) {
                showConfetti = false
            }
        }
    }
```

Replace with:
```swift
    private func revealSummary() {
        showConfetti = true

        withAnimation(.easeInOut(duration: 0.5)) {
            stage = .summary
        }
        // summaryOpacity stays at 0 — text reveal is driven by ConfettiView.onSettling
    }
```

**Step 3: Update ConfettiView call site to pass onSettling closure**

Find:
```swift
            if showConfetti {
                ConfettiView(isActive: $showConfetti, intensity: .high)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
```

Replace with:
```swift
            if showConfetti {
                ConfettiView(isActive: $showConfetti, intensity: .high, onSettling: {
                    withAnimation(.easeIn(duration: 0.6)) {
                        summaryOpacity = 1.0
                    }
                })
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
```

**Step 4: Build to verify no compile errors**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`.

**Step 5: Commit**

```bash
git add "Peezy 4.0/Assessment/AssessmentViews/Onboarding/AsessmentCompleteView.swift"
git commit -m "feat: choreograph summary text reveal via confetti onSettling callback"
```

---

### Task 3: Verify AnimatedAssessmentProgressBar still compiles

**Files:**
- Read: `Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift`

**Step 1: Read the file**

Read `Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift` — it uses `ConfettiView(isActive: $showConfetti, intensity: .high)`. Confirm the call site compiles with the new API (both `intensity` and `onSettling` are present; `onSettling` is optional so no change needed).

**Step 2: Confirm build still passes**

```bash
cd "/Users/adampowell/Desktop/Peezy 4.0" && xcodebuild \
  -project "Peezy 4.0.xcodeproj" \
  -scheme "Peezy 4.0" \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`. No changes needed to this file — `onSettling` defaults to `nil`.

**Step 3: Final commit if any fixes were needed**

If AnimatedAssessmentProgressBar required any adjustment (unlikely):
```bash
git add "Peezy 4.0/Assessment/AssessmentModels/AnimatedAssessmentProgressBar.swift"
git commit -m "fix: update AnimatedAssessmentProgressBar for new ConfettiView API"
```

---

## Summary of Changes

| File | Change |
|------|--------|
| `ConfettiView.swift` | Full rewrite: TimelineView+Canvas, top-down shower, rectangles+circles, vibrant palette, `onSettling` callback |
| `AsessmentCompleteView.swift` | `revealSummary()` simplified; `ConfettiView` call site passes `onSettling` to drive text fade-in |
| `AnimatedAssessmentProgressBar.swift` | No change needed — `onSettling` is optional, existing call site unchanged |

## Expected Behavior After Implementation

1. User taps "See Your Custom Plan"
2. Screen transitions to summary (text at opacity 0), confetti shower begins from top edge
3. ~100 paper rectangles and dots rain down with gravity, wobble, and tumbling rotation
4. At t=2.0s emission stops; remaining particles fall and fade
5. At t=2.2s `onSettling` fires → 0.6s fade-in begins on summary text
6. At t=2.8s text is fully visible
