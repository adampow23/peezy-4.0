import SwiftUI

enum PeezyDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case timeline = "Task List"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .timeline: return "checklist"
        case .settings: return "gear"
        }
    }
}

struct PeezyMenuView: View {
    @Binding var isOpen: Bool
    @Binding var selectedDestination: PeezyDestination
    let userName: String
    var onEditProfile: (() -> Void)? = nil

    private let menuBackground = PeezyTheme.Colors.lightBase

    var body: some View {
        ZStack(alignment: .leading) {
            // Dimmed background (tappable to close)
            if isOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isOpen = false
                        }
                    }
            }

            // Menu drawer
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header — tappable to edit profile
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isOpen = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onEditProfile?()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .bottom) {
                                Text("peezy")
                                    .font(.system(size: 24, weight: .light))
                                    .tracking(4)
                                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.9))

                                Spacer()

                                if !userName.isEmpty {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                                }
                            }

                            if !userName.isEmpty {
                                Text("Hi, \(userName)")
                                    .font(PeezyTheme.Typography.callout)
                                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(.peezySecondary)
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)

                    // Menu Items
                    VStack(spacing: 4) {
                        ForEach(PeezyDestination.allCases) { destination in
                            MenuRow(
                                destination: destination,
                                isSelected: selectedDestination == destination,
                                action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedDestination = destination
                                        isOpen = false
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)

                    Spacer()

                    // Version footer
                    Text("Version 1.0")
                        .font(PeezyTheme.Typography.caption)
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                }
                .frame(width: 280)
                .background(
                    ZStack {
                        menuBackground

                        // Subtle gradient overlay
                        LinearGradient(
                            colors: [.white.opacity(0.05), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()
                )

                Spacer()
            }
            .offset(x: isOpen ? 0 : -300)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOpen)
    }
}

// MARK: - Menu Row
struct MenuRow: View {
    let destination: PeezyDestination
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PeezyTheme.Layout.itemSpacing) {
                Image(systemName: destination.icon)
                    .font(.system(size: 20))
                    .frame(width: 28)

                Text(destination.rawValue)
                    .font(isSelected ? PeezyTheme.Typography.headline : PeezyTheme.Typography.body)

                Spacer()

                if isSelected {
                    Circle()
                        .fill(PeezyTheme.Colors.infoBlue)
                        .frame(width: 8, height: 8)
                }
            }
            .foregroundStyle(isSelected ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.55))
            .padding(.horizontal, PeezyTheme.Layout.cardPadding)
            .padding(.vertical, PeezyTheme.Layout.cardPaddingSmall)
            .background(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusSmall, style: .continuous)
                    .fill(isSelected ? PeezyTheme.Colors.deepInk.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.peezyPress)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PeezyMenuView(
            isOpen: .constant(true),
            selectedDestination: .constant(.home),
            userName: "Adam",
            onEditProfile: { }
        )
    }
}
