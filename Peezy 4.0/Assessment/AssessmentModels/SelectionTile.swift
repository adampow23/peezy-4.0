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
                        .foregroundColor(
                            isSelected
                                ? PeezyTheme.Colors.lightBase
                                : PeezyTheme.Colors.deepInk.opacity(0.12)
                        )
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: isSelected)
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(
                            isSelected
                                ? PeezyTheme.Colors.lightBase
                                : PeezyTheme.Colors.deepInk
                        )
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(
                                isSelected
                                    ? PeezyTheme.Colors.lightBase.opacity(0.6)
                                    : PeezyTheme.Colors.deepInk.opacity(0.5)
                            )
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: icon != nil ? 140 : 80)
            .background(
                ZStack {
                    // 1. Surface Gradients applied to both states
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [PeezyTheme.Colors.deepInk.opacity(0.85), PeezyTheme.Colors.deepInk],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white, Color(white: 0.98)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    // 2. Bevel/Highlight strokes for both selected and unselected states
                    .stroke(
                        LinearGradient(
                            colors: isSelected
                                ? [.white.opacity(0.3), .clear, .black.opacity(0.3)]
                                : [.white, .clear, .black.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            // 3. Grounded Drop Shadows that physically shrink when pressed
            .shadow(
                color: isSelected
                    ? PeezyTheme.Colors.deepInk.opacity(isPressed ? 0.15 : 0.3)
                    : Color.black.opacity(isPressed ? 0.05 : 0.08),
                radius: isPressed ? 4 : (isSelected ? 10 : 12),
                x: 0,
                y: isPressed ? 2 : (isSelected ? 4 : 8)
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
