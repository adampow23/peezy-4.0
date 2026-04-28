import SwiftUI

struct ResetInventoryOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
            ProgressView("Resetting inventory...")
                .font(PeezyTheme.Typography.callout)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
