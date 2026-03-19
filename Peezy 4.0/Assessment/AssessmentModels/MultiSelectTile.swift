import SwiftUI

struct MultiSelectTile: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void
    var count: Int = 0          // 0 = not selected, 1 = checkmark, 2+ = number badge

    @State private var isPressed = false

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

                // Right side — checkmark or count badge
                if isSelected {
                    if count > 1 {
                        // Number badge for multiple taps
                        Text("\(count)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(PeezyTheme.Colors.deepInk)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(PeezyTheme.Colors.lightBase)
                            )
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        // Single checkmark
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(PeezyTheme.Colors.lightBase.opacity(0.8))
                            .transition(.scale.combined(with: .opacity))
                    }
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
                            .fill(Color.white)
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
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
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
        MultiSelectTile(title: "Bank / Credit Union", icon: "building.columns.fill",
                        isSelected: false, onTap: {}, count: 0)
        MultiSelectTile(title: "Credit Card", icon: "creditcard.fill",
                        isSelected: true, onTap: {}, count: 1)
        MultiSelectTile(title: "Investment Account", icon: "chart.line.uptrend.xyaxis",
                        isSelected: true, onTap: {}, count: 3)
    }
    .padding()
    .background(InteractiveBackground())
}
