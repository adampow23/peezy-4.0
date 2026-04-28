import SwiftUI

struct TasksEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 50))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

            Text("No tasks yet")
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Text("Tasks will appear here after your assessment.")
                .font(PeezyTheme.Typography.callout)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

struct TasksTabEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(PeezyTheme.Typography.callout)
            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }
}
