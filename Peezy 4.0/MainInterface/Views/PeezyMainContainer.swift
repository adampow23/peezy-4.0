//
//  PeezyMainContainer.swift
//  Peezy
//
//  Main tab container for the app.
//  Three tabs: Home, Tasks, Settings.
//

import SwiftUI

struct PeezyMainContainer: View {
    // Navigation state
    @State private var selectedTab: PeezyTab = .home

    // User state passed from AppRootView
    @Binding var userState: UserState?

    // Timeline still uses PeezyStackViewModel for its data loading
    @State private var timelineViewModel = PeezyStackViewModel()
    @State private var hasLoadedTimeline = false

    // Task list → Home navigation: when set, switches to Home and focuses this task
    @State private var focusedTask: PeezyCard? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed background — spans entire screen including safe areas
            InteractiveBackground()
                .ignoresSafeArea()

            // Main content
            Group {
                switch selectedTab {
                case .home:
                    PeezyHomeView(userState: userState, focusedTask: $focusedTask)

                case .tasks:
                    PeezyTaskStream(
                        viewModel: timelineViewModel,
                        userState: userState,
                        onNavigateToTask: { task in
                            focusedTask = task
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = .home
                            }
                        }
                    )

                case .settings:
                    PeezySettingsView(userState: $userState)
                }
            }

            // Floating tab bar
            PeezyFloatingTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 16)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .tasks && !hasLoadedTimeline {
                timelineViewModel.userState = userState
                Task {
                    await timelineViewModel.loadInitialCards()
                    hasLoadedTimeline = true
                }
            }
        }
    }
}

// MARK: - Tab Enum

enum PeezyTab: String, CaseIterable {
    case home
    case tasks
    case settings

    var icon: String {
        switch self {
        case .home:     return "house"
        case .tasks:    return "checklist"
        case .settings: return "gearshape"
        }
    }

    var label: String {
        switch self {
        case .home:     return "Home"
        case .tasks:    return "Tasks"
        case .settings: return "Settings"
        }
    }
}

// MARK: - Floating Tab Bar

struct PeezyFloatingTabBar: View {
    @Binding var selectedTab: PeezyTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeezyTab.allCases, id: \.self) { tab in
                Button {
                    PeezyHaptics.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            selectedTab == tab
                                ? PeezyTheme.Colors.deepInk
                                : PeezyTheme.Colors.deepInk.opacity(0.3)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
        }
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 5)
        )
        .frame(width: 200)
    }
}
