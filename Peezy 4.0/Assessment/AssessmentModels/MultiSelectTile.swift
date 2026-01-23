import SwiftUI

struct MultiSelectTile: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    // Charcoal glass color
    private let charcoalColor = PeezyTheme.Colors.charcoalGlass
    private let accentBlue = PeezyTheme.Colors.accentBlue

    var body: some View {
        Button(action: {
            lightHaptic.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                // Icon on left
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 32)

                // Text in center
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Checkmark on right
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(accentBlue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Glass blur effect
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Charcoal tint (darker when selected)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(charcoalColor.opacity(isSelected ? 0.8 : 0.6))
                }
            )
            .overlay(
                // Edge highlight (brighter when selected)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? accentBlue.opacity(0.6) : Color.white.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected ? accentBlue.opacity(0.2) : Color.black.opacity(0.3),
                radius: isPressed ? 3 : 8,
                x: 0,
                y: isPressed ? 1 : 4
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        isPressed = false
                    }
                }
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        MultiSelectTile(
            title: "Building my to-do list",
            icon: "list.bullet.clipboard",
            isSelected: true,
            onTap: { print("Tapped") }
        )
        
        MultiSelectTile(
            title: "Packing/preparing for move day",
            icon: "shippingbox.fill",
            isSelected: false,
            onTap: { print("Tapped") }
        )
        
        MultiSelectTile(
            title: "Finding reliable professionals (movers, cleaners, etc.)",
            icon: "person.fill.questionmark.rtl",
            isSelected: true,
            onTap: { print("Tapped") }
        )
        
        MultiSelectTile(
            title: "Planning/staying on track",
            icon: "calendar",
            isSelected: false,
            onTap: { print("Tapped") }
        )
        
        MultiSelectTile(
            title: "Other",
            icon: "ellipsis",
            isSelected: false,
            onTap: { print("Tapped") }
        )
    }
    .padding()
    .background(InteractiveBackground())
}
