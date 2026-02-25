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
                // Icon on left — cutout style
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(
                        isSelected
                            ? PeezyTheme.Colors.lightBase
                            : PeezyTheme.Colors.deepInk.opacity(0.12)
                    )
                    .frame(width: 32)

                // Text in center
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(
                        isSelected
                            ? PeezyTheme.Colors.lightBase
                            : PeezyTheme.Colors.deepInk
                    )
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Checkmark on right
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(PeezyTheme.Colors.lightBase.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(PeezyTheme.Colors.deepInk)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.15))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? Color.clear
                            : Color.black.opacity(0.05),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isSelected
                    ? PeezyTheme.Colors.deepInk.opacity(0.25)
                    : Color.black.opacity(0.1),
                radius: isPressed ? 3 : (isSelected ? 10 : 12),
                x: 0,
                y: isPressed ? 1 : (isSelected ? 4 : 8)
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
