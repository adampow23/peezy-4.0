import SwiftUI

struct MultiSelectTile: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void
    var count: Int = 0
    var onIncrement: (() -> Void)? = nil
    var onDecrement: (() -> Void)? = nil

    @State private var isPressed = false

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
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

            // Right side — +/- controls or checkmark when selected
            if isSelected {
                if onIncrement != nil {
                    HStack(spacing: 8) {
                        Button(action: { onDecrement?() }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(PeezyTheme.Colors.lightBase.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        Text("\(count)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(PeezyTheme.Colors.lightBase)
                            .frame(minWidth: 24)

                        Button(action: { onIncrement?() }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(PeezyTheme.Colors.lightBase.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PeezyTheme.Colors.lightBase.opacity(0.8))
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if isSelected {
                // In binary mode (no counter), allow deselect by tapping
                if onIncrement == nil {
                    lightHaptic.impactOccurred()
                    onTap()
                }
                // In counter mode, do nothing — use +/- buttons
            } else {
                lightHaptic.impactOccurred()
                onTap()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isSelected else { return }
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
                        isSelected: true, onTap: {}, count: 1,
                        onIncrement: {}, onDecrement: {})
        MultiSelectTile(title: "Investment Account", icon: "chart.line.uptrend.xyaxis",
                        isSelected: true, onTap: {}, count: 3,
                        onIncrement: {}, onDecrement: {})
    }
    .padding()
    .background(InteractiveBackground())
}
