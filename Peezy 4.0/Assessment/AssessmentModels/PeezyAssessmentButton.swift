import SwiftUI

struct PeezyAssessmentButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    // Animation states
    @State private var isPressed = false

    // Haptic feedback
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)

    // Charcoal glass color (Assuming this exists in your theme)
    private let deepInk = PeezyTheme.Colors.deepInk

    init(_ title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            mediumHaptic.impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(disabled ? .white.opacity(0.5) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    ZStack {
                        // Main button body - Solid for contrast, matching the selected SelectionTile
                        Capsule(style: .continuous)
                            .fill(deepInk.opacity(disabled ? 0.3 : 1.0))
                    }
                )
                .overlay(
                    // Subtle top edge highlight to give a 3D, polished glass feel
                    Capsule(style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(disabled ? 0.0 : 0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                // The "Glow" - A diffused shadow matching the button's color
                .shadow(
                    color: disabled ? .clear : deepInk.opacity(isPressed ? 0.2 : 0.4),
                    radius: isPressed ? 8 : 16,
                    x: 0,
                    y: isPressed ? 4 : 8
                )
        }
        .disabled(disabled)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        // Matched the spring animation from your SelectionTile for consistency
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: disabled) // Smooth transition if disabled state changes
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !disabled && !isPressed {
                        let lightHaptic = UIImpactFeedbackGenerator(style: .light)
                        lightHaptic.impactOccurred()
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        // Fallback color in case InteractiveBackground isn't in scope for the preview
        Color(white: 0.95).ignoresSafeArea()

        VStack(spacing: 32) {
            PeezyAssessmentButton("Continue") {
                print("Continue tapped")
            }

            PeezyAssessmentButton("Start Assessment") {
                print("Start tapped")
            }

            PeezyAssessmentButton("Continue", disabled: true) {
                print("This won't fire")
            }
        }
        .padding(.horizontal, 24)
    }
}
