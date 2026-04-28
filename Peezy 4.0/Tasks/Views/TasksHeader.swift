import SwiftUI

struct TasksHeader: View {
    let userName: String?
    let onNavigateHome: (() -> Void)?

    private var headerTitle: String {
        if let userName, !userName.isEmpty {
            let firstName = userName.split(separator: " ").first.map(String.init) ?? userName
            return "\(firstName)'s Task List"
        }
        return "Task List"
    }

    var body: some View {
        HStack {
            Text(headerTitle)
                .font(PeezyTheme.Typography.title2)
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Spacer()

            if let onNavigateHome {
                Button(action: onNavigateHome) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial.opacity(0.8))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Return to home")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}
