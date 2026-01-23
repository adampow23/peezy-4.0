import SwiftUI

struct PeezyAssessmentButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    // Animation states
    @State private var isPressed = false

    // Haptic feedback
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)

    // Charcoal glass color
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass

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
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(disabled ? .white.opacity(0.4) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    ZStack {
                        // Glass blur effect
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(.ultraThinMaterial)

                        // Charcoal tint
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(charcoalColor.opacity(disabled ? 0.4 : 0.6))
                    }
                )
                .overlay(
                    // Edge highlight
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(disabled ? 0.05 : 0.1), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(disabled ? 0.1 : 0.3),
                    radius: isPressed ? 8 : 15,
                    x: 0,
                    y: isPressed ? 4 : 8
                )
        }
        .disabled(disabled)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !disabled {
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
        InteractiveBackground()

        VStack(spacing: 24) {
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
