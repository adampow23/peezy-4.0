import SwiftUI

struct PeezyMainContainer: View {
    // Navigation state
    @State private var showMenu = false
    @State private var selectedDestination: PeezyDestination = .home

    // Shared state - viewModel is shared between Stack and Timeline views
    var userState: UserState?
    @State private var viewModel = PeezyStackViewModel()
    @State private var hasLoadedCards = false

    var body: some View {
        ZStack {
            // Main content based on selection
            Group {
                switch selectedDestination {
                case .home:
                    let _ = print("🏠 HOME: viewModel.cards.count = \(viewModel.cards.count)")
                    PeezyStackViewWithWorkflow(viewModel: viewModel, userState: userState)

                case .timeline:
                    let _ = print("📅 TIMELINE: viewModel.cards.count = \(viewModel.cards.count)")
                    PeezyTaskStream(viewModel: viewModel, userState: userState)

                case .settings:
                    SettingsPlaceholderView()

                case .account:
                    AccountPlaceholderView()
                }
            }

            // Hamburger button (always visible)
            VStack {
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showMenu = true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 8)

                    Spacer()
                }
                Spacer()
            }

            // Menu overlay
            PeezyMenuView(
                isOpen: $showMenu,
                selectedDestination: $selectedDestination,
                userName: userState?.name ?? ""
            )
        }
        .onAppear {
            // Load cards ONCE at container level - shared across all child views
            if !hasLoadedCards {
                viewModel.userState = userState
                Task {
                    await viewModel.loadInitialCards()
                    hasLoadedCards = true
                    print("📦 Container loaded \(viewModel.cards.count) cards")
                }
            }
        }
    }
}

// MARK: - Placeholder Views
struct SettingsPlaceholderView: View {
    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 16) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.6))

                Text("Settings")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

struct AccountPlaceholderView: View {
    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.6))

                Text("Account")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

#Preview {
    PeezyMainContainer(userState: UserState(userId: "preview", name: "Adam"))
}
