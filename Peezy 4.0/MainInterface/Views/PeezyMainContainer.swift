//
//  PeezyMainContainer.swift
//  Peezy
//
//  Main container with hamburger menu navigation.
//  Home tab uses PeezyHomeView (new state machine).
//  Timeline tab uses PeezyTaskStream (unchanged, loads its own data).
//
//  CHANGES FROM PREVIOUS VERSION:
//  - .home → PeezyHomeView (was PeezyStackViewWithWorkflow)
//  - Timeline gets its own PeezyStackViewModel (was shared)
//  - Removed upfront card loading (each view loads its own data)
//  - Wrapped in PeezyWalkthrough for guided tour (shows once after paywall)
//  - Added .walkthroughStep() modifiers to 4 key UI elements
//

import SwiftUI

struct PeezyMainContainer: View {
    // Navigation state
    @State private var showMenu = false
    @State private var selectedDestination: PeezyDestination = .home

    // User state passed from AppRootView
    @Binding var userState: UserState?

    // Timeline still uses PeezyStackViewModel for its data loading
    @State private var timelineViewModel = PeezyStackViewModel()
    @State private var hasLoadedTimeline = false

    // Demo workflow trigger — set when walkthrough finishes
    @State private var startDemo = false

    var body: some View {
        PeezyWalkthrough(appStorageID: "PeezyGuidedTour") {
            ZStack {
                // Main content based on selection
                Group {
                    switch selectedDestination {
                    case .home:
                        PeezyHomeView(userState: userState, startDemo: $startDemo)

                    case .timeline:
                        PeezyTaskStream(viewModel: timelineViewModel, userState: userState)

                    case .settings:
                        PeezySettingsView(userState: $userState)

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
                        .walkthroughStep(3, cornerRadius: 22) {
                            WalkthroughStepView(
                                title: "Your Move Details",
                                body: "Tap the menu to update your move date, address, or household info. Peezy adjusts your entire plan automatically."
                            )
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
        } onFinished: {
            startDemo = true
        }
        .onAppear {
            // Defensive: clean up zombie walkthrough overlay windows
            if UserDefaults.standard.bool(forKey: "PeezyGuidedTour"),
               let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let stale = scene.windows.first(where: { $0.tag == 1009 }) {
                stale.isUserInteractionEnabled = false
                stale.isHidden = true
                stale.rootViewController = nil
            }
        }
        .onChange(of: selectedDestination) { _, newValue in
            // Lazy-load timeline data when user navigates to it
            if newValue == .timeline && !hasLoadedTimeline {
                timelineViewModel.userState = userState
                Task {
                    await timelineViewModel.loadInitialCards()
                    hasLoadedTimeline = true
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
    PeezyMainContainer(userState: .constant(UserState(userId: "preview", name: "Adam")))
}
