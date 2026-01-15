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
                        .foregroundColor(PeezyTheme.Colors.brandYellow)
                        .scaleEffect(isSelected ? 1.0 : 1.0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: isSelected)
                }
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: icon != nil ? 140 : 80)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.clear)
                        .peezyLiquidGlass(
                            cornerRadius: 20,
                            intensity: 0.55,
                            speed: 0.22,
                            tintOpacity: 0.05,
                            highlightOpacity: 0.12
                        )
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.35))
                    
                    // Flash effect on selection
                    if isSelected {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.3))
                            .transition(.opacity)
                    }
                }
            )
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? PeezyTheme.Colors.brandYellow : Color.clear, lineWidth: 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
            )
            .shadow(
                color: Color.black.opacity(isPressed ? 0 : 0.1),
                radius: isPressed ? 0 : 8,
                x: 0,
                y: isPressed ? 0 : 4
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .opacity(isSelected ? 1.0 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
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
