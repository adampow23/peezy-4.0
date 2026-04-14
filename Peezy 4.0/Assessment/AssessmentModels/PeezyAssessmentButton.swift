import SwiftUI

// MARK: - Peezy Press Button Style

struct PeezyPressButtonStyle: ButtonStyle {
    let disabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Slightly deeper scale effect for a more physical press feel
            .scaleEffect(configuration.isPressed && !disabled ? 0.96 : 1.0)
            .shadow(
                color: disabled ? .clear : PeezyTheme.Colors.deepInk.opacity(configuration.isPressed ? 0.15 : 0.35),
                // Radius and Y offset shrink when pressed to simulate the button hitting the floor
                radius: configuration.isPressed ? 4 : 14,
                x: 0,
                y: configuration.isPressed ? 2 : 8
            )
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Peezy Assessment Button

struct PeezyAssessmentButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void

    private let deepInk = PeezyTheme.Colors.deepInk

    init(_ title: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            PeezyHaptics.medium()
            action()
        }) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(disabled ? .white.opacity(0.5) : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        // 1. Surface Gradient: Slightly lighter at the top to simulate a curved, physical surface
                        .fill(
                            LinearGradient(
                                colors: [
                                    deepInk.opacity(disabled ? 0.3 : 0.85),
                                    deepInk.opacity(disabled ? 0.3 : 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        // 2. Bevel/Highlight: Crisp white line at the top edge catching the light, dark shadow at the bottom
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(disabled ? 0.0 : 0.35),
                                    .clear,
                                    .black.opacity(disabled ? 0.0 : 0.4)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
        }
        .disabled(disabled)
        .buttonStyle(PeezyPressButtonStyle(disabled: disabled))
        .animation(.easeInOut(duration: 0.2), value: disabled)
    }
}
