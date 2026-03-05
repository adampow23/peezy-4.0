//
//  PeezyMainContainer.swift
//  Peezy
//
//  Main container with hamburger menu navigation.
//  Home tab uses PeezyHomeView (new state machine).
//  Timeline tab uses PeezyTaskStream (unchanged, loads its own data).
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

    // Task list → Home navigation: when set, switches to Home and focuses this task
    @State private var focusedTask: PeezyCard? = nil

    // Edit profile sheet — triggered from menu header tap
    @State private var showEditProfile = false

    var body: some View {
        ZStack {
            // Main content based on selection
            Group {
                switch selectedDestination {
                case .home:
                    PeezyHomeView(userState: userState, focusedTask: $focusedTask)

                case .timeline:
                    PeezyTaskStream(viewModel: timelineViewModel, userState: userState) { task in
                        focusedTask = task
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedDestination = .home
                        }
                    }

                case .settings:
                    PeezySettingsView(userState: $userState)
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
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 8)

                    Spacer()

                    // Task list button (top right)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedDestination = .timeline
                        }
                    } label: {
                        Image(systemName: "checklist")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }

            // Menu overlay
            PeezyMenuView(
                isOpen: $showMenu,
                selectedDestination: $selectedDestination,
                userName: userState?.name ?? "",
                onEditProfile: {
                    showEditProfile = true
                }
            )
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
        .sheet(isPresented: $showEditProfile) {
            EditNameEmailSheet(userState: userState) { updatedName in
                userState?.name = updatedName
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
                    .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))

                Text("Settings")
                    .font(.title2.bold())
                    .foregroundStyle(PeezyTheme.Colors.deepInk)

                Text("Coming soon")
                    .font(.subheadline)
                    .foregroundStyle(Color.gray)
            }
        }
    }
}

#Preview {
    PeezyMainContainer(userState: .constant(UserState(userId: "preview", name: "Adam")))
}
