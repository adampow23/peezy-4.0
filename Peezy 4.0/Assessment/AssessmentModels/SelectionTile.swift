import SwiftUI

struct SelectionTile: View {
    let title: String
    let subtitle: String?
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)

    // Charcoal glass color
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass
    private let accentBlue = PeezyTheme.Colors.accentBlue

    init(title: String, subtitle: String? = nil, icon: String? = nil, isSelected: Bool, onTap: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        Button(action: {
            mediumHaptic.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 16) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: isSelected)
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: icon != nil ? 140 : 80)
            .background(
                ZStack {
                    // Glass blur effect
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Charcoal tint (darker when selected)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(charcoalColor.opacity(isSelected ? 0.8 : 0.6))
                }
            )
            .overlay(
                // Edge highlight (brighter when selected)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        isSelected ? accentBlue.opacity(0.6) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? accentBlue.opacity(0.3) : Color.black.opacity(0.3),
                radius: isPressed ? 5 : 12,
                x: 0,
                y: isPressed ? 2 : 6
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    lightHaptic.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }
}
