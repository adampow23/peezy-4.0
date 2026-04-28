import SwiftUI

struct SecondaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule(style: .continuous)
                        .stroke(PeezyTheme.Colors.deepInk, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
