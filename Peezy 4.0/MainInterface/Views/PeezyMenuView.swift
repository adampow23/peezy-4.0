import SwiftUI

enum PeezyDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case timeline = "Timeline"
    case settings = "Settings"
    case account = "Account"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "square.stack.3d.up.fill"
        case .timeline: return "calendar.badge.clock"
        case .settings: return "gearshape.fill"
        case .account: return "person.circle.fill"
        }
    }
}

struct PeezyMenuView: View {
    @Binding var isOpen: Bool
    @Binding var selectedDestination: PeezyDestination
    let userName: String

    // Charcoal color matching app theme
    private let charcoalColor = Color(red: 0.12, green: 0.12, blue: 0.14)

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
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.9))

                        Text("peezy")
                            .font(.system(size: 24, weight: .light))
                            .tracking(4)
                            .foregroundStyle(.white.opacity(0.9))

                        if !userName.isEmpty {
                            Text("Hi, \(userName)")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
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
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                }
                .frame(width: 280)
                .background(
                    ZStack {
                        charcoalColor

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
            HStack(spacing: 16) {
                Image(systemName: destination.icon)
                    .font(.system(size: 20))
                    .frame(width: 28)

                Text(destination.rawValue)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))

                Spacer()

                if isSelected {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 8, height: 8)
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        PeezyMenuView(
            isOpen: .constant(true),
            selectedDestination: .constant(.home),
            userName: "Adam"
        )
    }
}
