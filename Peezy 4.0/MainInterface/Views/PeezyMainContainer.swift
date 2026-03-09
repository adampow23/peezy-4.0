//
//  PeezyMainContainer.swift
//  Peezy
//
//  Main app container with floating tab bar.
//  Four tabs: Home, Tasks, Chat, Settings.
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

                case .chat:
                    ChatView(userState: userState, card: nil)

                case .settings:
                    PeezySettingsView(userState: $userState)
                }
            }

            // Floating tab bar
            PeezyFloatingTabBar(selectedTab: $selectedTab)
        }
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
    case chat
    case settings

    var icon: String {
        switch self {
        case .home:     return "house"
        case .tasks:    return "checklist"
        case .chat:     return "bubble.left"
        case .settings: return "gearshape"
        }
    }

    var label: String {
        switch self {
        case .home:     return "Home"
        case .tasks:    return "Tasks"
        case .chat:     return "Chat"
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
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .medium))

                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(
                        selectedTab == tab
                            ? PeezyTheme.Colors.deepInk.opacity(0.8)
                            : PeezyTheme.Colors.deepInk.opacity(0.2)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.peezyTab)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 14) // Safe area breathing room
        .background(
            Capsule()
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.06), radius: 12, y: 4)
                .padding(.horizontal, 24)
        )
    }
}

#Preview {
    PeezyMainContainer(userState: .constant(UserState(userId: "preview", name: "Adam")))
}
