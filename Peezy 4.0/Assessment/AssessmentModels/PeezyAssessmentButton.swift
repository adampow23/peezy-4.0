import SwiftUI

struct PeezyAssessmentButton: View {
    let title: String
    let disabled: Bool
    let action: () -> Void
    
    // Animation states
    @State private var isPressed = false
    
    // Haptic feedback
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    
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
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(disabled ? .black.opacity(0.35) : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    ZStack {
                        // Liquid glass base
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.clear)
                            .peezyLiquidGlass(
                                cornerRadius: 20,
                                intensity: 0.55,
                                speed: 0.22,
                                tintOpacity: 0.05,
                                highlightOpacity: 0.12
                            )
                        
                        // Fill layer
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                disabled
                                    ? Color.gray.opacity(0.15)
                                    : PeezyTheme.Colors.brandYellow.opacity(0.6)
                            )
                        
                        // Stroke border
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(
                                disabled
                                    ? Color.gray.opacity(0.3)
                                    : PeezyTheme.Colors.brandYellow.opacity(0.35),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(
                    color: disabled ? Color.clear : PeezyTheme.Colors.brandYellow.opacity(0.25),
                    radius: isPressed ? 4 : 8,
                    x: 0,
                    y: isPressed ? 2 : 4
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
    VStack(spacing: 24) {
        Text("PeezyAssessmentButton")
            .font(.headline)
        
        PeezyAssessmentButton("Continue") {
            print("Continue tapped")
        }
        
        PeezyAssessmentButton("Start Assessment") {
            print("Start tapped")
        }
        
        PeezyAssessmentButton("Get Started") {
            print("Get Started tapped")
        }
        
        PeezyAssessmentButton("Continue", disabled: true) {
            print("This won't fire")
        }
    }
    .padding(.horizontal, 24)
}
