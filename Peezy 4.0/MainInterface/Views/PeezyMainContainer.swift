//
//  PeezyMainContainer.swift
//  Peezy
//
//  Main tab container for the app.
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

    // Support chat service — owned here so the unread badge updates regardless of which tab is active
    @State private var chatService = SupportChatService()

    // Task list → Home navigation: when set, switches to Home and focuses this task
    @State private var focusedTask: PeezyCard? = nil

    // Measured height of the floating tab bar (including its bottom padding)
    @State private var tabBarHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed background — spans entire screen including safe areas
            InteractiveBackground()
                .ignoresSafeArea()

            // Main content — inset so nothing hides behind the floating tab bar
            Group {
                switch selectedTab {
                case .home:
                    PeezyHomeView(userState: userState, focusedTask: $focusedTask)
                        .ignoresSafeArea(.keyboard, edges: .bottom)

                case .tasks:
                    PeezyTaskStream(
                        viewModel: timelineViewModel,
                        userState: userState,
                        onNavigateToTask: { task in
                            focusedTask = task
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = .home
                            }
                        }
                    )
                    .ignoresSafeArea(.keyboard, edges: .bottom)

                case .chat:
                    SupportChatView(userState: userState)

                case .settings:
                    PeezySettingsView(userState: $userState)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: tabBarHeight)
            }

            // Floating tab bar — height is measured and fed back into tabBarHeight
            PeezyFloatingTabBar(selectedTab: $selectedTab, chatUnreadCount: chatService.unreadCount)
                .padding(.bottom, 16)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    tabBarHeight = height
                }
        }
        .onAppear {
            chatService.startListening()
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
        case .chat:     return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home:     return "house.fill"
        case .tasks:    return "checklist"       // no filled SF Symbol variant
        case .chat:     return "bubble.left.and.bubble.right.fill"
        case .settings: return "gearshape.fill"
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
    var chatUnreadCount: Int = 0
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeezyTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                let showUnreadDot = tab == .chat && chatUnreadCount > 0 && !isSelected
                Button {
                    PeezyHaptics.light()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Label(tab.label, systemImage: isSelected ? tab.selectedIcon : tab.icon)
                        .labelStyle(.iconOnly)
                        .font(.system(size: tabIconSize, weight: .medium))
                        .foregroundStyle(
                            isSelected
                                ? PeezyTheme.Colors.deepInk
                                : PeezyTheme.Colors.deepInk.opacity(0.3)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(alignment: .topTrailing) {
                            if showUnreadDot {
                                Circle()
                                    .fill(PeezyTheme.Colors.emotionalRed)
                                    .frame(width: 8, height: 8)
                                    .offset(x: -10, y: 12)
                                    .accessibilityIdentifier("chat_unread_badge")
                            }
                        }
                }
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isSelected ? "" : "Switches to \(tab.label) tab")
                .accessibilityIdentifier("tab_\(tab.rawValue)")
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
        .frame(width: 240)
    }
}
