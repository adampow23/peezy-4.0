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
                // 1. Surface Gradients applied to both states
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [PeezyTheme.Colors.deepInk.opacity(0.85), PeezyTheme.Colors.deepInk],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
            radius: isPressed ? 4 : 12,
            x: 0,
            y: isPressed ? 2 : 6
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if isSelected {
                if onIncrement == nil {
                    lightHaptic.impactOccurred()
                    onTap()
                }
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
