import SwiftUI

struct TasksErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(PeezyTheme.Colors.warningOrange)

            Text("Couldn't load tasks")
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Text(message)
                .font(PeezyTheme.Typography.footnote)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button {
                PeezyHaptics.light()
                onRetry()
            } label: {
                Text("Tap to retry")
                    .font(PeezyTheme.Typography.calloutMedium)
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(PeezyTheme.Colors.deepInk, lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
