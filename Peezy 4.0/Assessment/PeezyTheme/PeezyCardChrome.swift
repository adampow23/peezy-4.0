import SwiftUI

// MARK: - Unified Card Chrome
// Single source of truth for the glass card appearance.
// Apply to ALL home screen cards for visual consistency.

struct PeezyCardChrome: ViewModifier {
    var width: CGFloat = 340
    var maxHeight: CGFloat = 500

    func body(content: Content) -> some View {
        ZStack {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .foregroundStyle(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color.white.opacity(0.7))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    .padding(1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 15)

            content
        }
        .frame(width: width)
        .frame(maxHeight: maxHeight)
    }
}

extension View {
    func peezyCardChrome(width: CGFloat = 340, maxHeight: CGFloat = 500) -> some View {
        modifier(PeezyCardChrome(width: width, maxHeight: maxHeight))
    }
}
