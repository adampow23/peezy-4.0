import SwiftUI

struct MultiSelectTile: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isPressed = false

    // Haptic feedback
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Button(action: {
            lightHaptic.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                // Icon on left
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.primary)
                    .frame(width: 32)
                
                // Text in center
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Checkmark on right
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.clear)
                        .peezyLiquidGlass(
                            cornerRadius: 12,
                            intensity: 0.55,
                            speed: 0.22,
                            tintOpacity: 0.05,
                            highlightOpacity: 0.12
                        )
                    
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.35))
                    
                    // Flash effect on selection
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.3))
                            .transition(.opacity)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? PeezyTheme.Colors.brandYellow : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
            )
            .shadow(
                color: Color.black.opacity(isPressed ? 0 : 0.08),
                radius: isPressed ? 0 : 6,
                x: 0,
                y: isPressed ? 0 : 3
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
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
    .background(Color(.systemGroupedBackground))
}
