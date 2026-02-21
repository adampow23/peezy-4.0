# Confetti Redesign — Design Doc
**Date:** 2026-02-21
**Files:** `Peezy 4.0/Assessment/PeezyTheme/ConfettiView.swift`, `Peezy 4.0/Assessment/AssessmentViews/Onboarding/AsessmentCompleteView.swift`

## Problem

Current confetti uses checkmark and star SF Symbols — these look like UI icons, not celebration confetti. The burst originates from screen center (not top-down like real confetti). Text and confetti appear simultaneously with no choreographed reveal.

## Approach

`TimelineView(.animation)` + `Canvas` renderer. Particle physics in a value-type array updated per frame. No SwiftUI per-particle views — zero diffing cost at 60fps.

## ConfettiView Changes

### Particle shapes
- Remove: `checkmark`, `star`
- Keep: `.circle` — diameter 4–6pt
- Add: `.rectangle(width: CGFloat, height: CGFloat)` — width 6–12pt, height 4–8pt, random aspect ratio

### Colors (vibrant palette)
- Gold/yellow: `Color(red: 0.98, green: 0.85, blue: 0.29)` (existing)
- White
- Light blue: `Color(red: 0.45, green: 0.78, blue: 0.98)`
- Coral/salmon: `Color(red: 0.98, green: 0.50, blue: 0.45)`
- Mint green: `Color(red: 0.45, green: 0.88, blue: 0.70)`
- Soft purple: `Color(red: 0.75, green: 0.55, blue: 0.95)`

### Physics
- Emission origin: `x` random across full screen width, `y = -10`
- Initial `velocity.dy`: 180–320 pt/s downward
- Initial `velocity.dx`: ±30–80 pt/s
- Per-frame gravity: `+380 pt/s²` added to `velocity.dy`
- Horizontal wobble: `sin(elapsedTime * wobbleFreq + wobblePhase) * 18` added to `dx` each frame
- Fade: begins at `y > screenHeight * 0.75`, particle removed at `y > screenHeight + 20` or `opacity ≤ 0`

### Emission schedule
- `t = 0.0–2.0s`: emit ~6–8 particles per batch every ~0.08s (~75–100 total)
- `t > 2.0s`: no new particles
- `t = 2.2s`: fire `onSettling()` once

### Renderer
`TimelineView(.animation)` → `Canvas` → per frame:
1. Compute `dt` from last frame timestamp
2. Update all particle positions/velocities/rotations/opacities
3. Draw `.rectangle` using `context.transform` rotation + filled rect
4. Draw `.circle` as filled ellipse

### API change
```swift
struct ConfettiView: View {
    @Binding var isActive: Bool
    let intensity: ConfettiIntensity
    var onSettling: (() -> Void)? = nil
}
```

## AssessmentCompleteView Changes

### `revealSummary()` rewrite
- Remove `summaryOpacity` fade-in with `.delay(0.3)` — text starts hidden
- Remove `DispatchQueue.main.asyncAfter(deadline: .now() + 4.0)` confetti stop timer
- Set `showConfetti = true`, transition to `.summary` stage — `summaryOpacity` stays at `0`

### ConfettiView call site
```swift
ConfettiView(isActive: $showConfetti, intensity: .high, onSettling: {
    withAnimation(.easeIn(duration: 0.6)) {
        summaryOpacity = 1.0
    }
})
```

### Timing result
| Time | Event |
|------|-------|
| t=0 | Confetti shower begins, summary at opacity 0 |
| t=2.0s | Emission stops, particles continue falling |
| t=2.2s | `onSettling()` fires, fade-in begins |
| t=2.8s | Text fully visible |

## What Does NOT Change
- `ConfettiIntensity` enum (keep for AnimatedAssessmentProgressBar compatibility)
- `summaryView` structure — `.opacity(summaryOpacity)` already wraps it
- Stage machine in AssessmentCompleteView
- `CheckmarkShape`, loading sequence, ready stage
