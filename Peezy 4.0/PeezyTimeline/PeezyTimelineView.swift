//
//  PeezyTimelineView.swift
//  Peezy
//
//  Tabbed task list: To-Do | In Progress | Later | Done
//  Data source: TimelineService (unchanged)
//

import SwiftUI

// MARK: - Tab Enum

enum TaskTab: String, CaseIterable {
    case todo = "To-Do"
    case inProgress = "In Progress"
    case later = "Later"
    case done = "Done"
}

// MARK: - Main View

struct PeezyTaskStream: View {
    // External data (kept for container compatibility)
    var viewModel: PeezyStackViewModel?
    var userState: UserState?

    // Navigation callback — switches to Home tab with focused task
    var onNavigateToTask: ((PeezyCard) -> Void)?

    // Task data from Firestore
    @State private var allTasks: [PeezyCard] = []
    @State private var isLoading = true

    // Expandable row tracking
    @State private var expandedTaskId: String? = nil

    // Active tab
    @State private var selectedTab: TaskTab = .todo

    // Preview/test data injection
    private var previewTasks: [PeezyCard]?

    // Init for standalone use (preview/testing)
    init() {
        self.viewModel = nil
        self.userState = nil
        self.onNavigateToTask = nil
        self.previewTasks = nil
    }

    // Init for integrated use
    init(viewModel: PeezyStackViewModel?, userState: UserState?, onNavigateToTask: ((PeezyCard) -> Void)? = nil) {
        self.viewModel = viewModel
        self.userState = userState
        self.onNavigateToTask = onNavigateToTask
        self.previewTasks = nil
    }

    // Init with sample data for previews
    init(previewTasks: [PeezyCard]) {
        self.viewModel = nil
        self.userState = nil
        self.onNavigateToTask = nil
        self.previewTasks = previewTasks
    }

    // MARK: - Grouped Tasks (4 sections)

    /// Section 1: "To-Do" — status = Upcoming (the full todo list)
    private var allUpcomingTasks: [PeezyCard] {
        allTasks.filter { card in
            card.status != .completed && card.status != .skipped
            && card.status != .inProgress && card.status != .userInProgress
            && !isSnoozed(card)
        }
        .sorted { a, b in
            let ua = a.urgencyPercentage ?? 0
            let ub = b.urgencyPercentage ?? 0
            if ua != ub { return ua > ub }
            return a.title < b.title
        }
    }

    /// Section 2a: "You're on it" — status = UserInProgress
    private var userInProgressTasks: [PeezyCard] {
        allTasks.filter { $0.status == .userInProgress }
            .sorted { ($0.userInProgressReturnDate ?? .distantFuture) < ($1.userInProgressReturnDate ?? .distantFuture) }
    }

    /// Section 2b: "Peezy is on it" — status = InProgress
    private var inProgressTasks: [PeezyCard] {
        allTasks.filter { $0.status == .inProgress }
            .sorted { a, b in
                if a.priority.rawValue != b.priority.rawValue {
                    return a.priority.rawValue > b.priority.rawValue
                }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    /// Section 3: "Later" — status = Snoozed
    private var snoozedTasks: [PeezyCard] {
        allTasks.filter { isSnoozed($0) }
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }
    }

    /// Section 4: "Done" — status = Completed
    private var completedTasks: [PeezyCard] {
        allTasks.filter { $0.status == .completed }
    }

    private func isSnoozed(_ card: PeezyCard) -> Bool {
        guard card.status != .completed else { return false }
        if card.status == .snoozed { return true }
        if let snoozedUntil = card.snoozedUntil, snoozedUntil > DateProvider.shared.now {
            return true
        }
        return false
    }

    // MARK: - Tab Counts

    private func taskCount(for tab: TaskTab) -> Int {
        switch tab {
        case .todo:       return allUpcomingTasks.count
        case .inProgress: return userInProgressTasks.count + inProgressTasks.count
        case .later:      return snoozedTasks.count
        case .done:       return completedTasks.count
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {
                headerView

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(PeezyTheme.Colors.deepInk)
                    Spacer()
                } else if allTasks.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    tabBar
                    tabContent
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .task {
            if let previewTasks {
                allTasks = previewTasks
                isLoading = false
            } else {
                await loadTasks()
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Task List")
                .font(.title2.bold())
                .foregroundColor(PeezyTheme.Colors.deepInk)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 16)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                        expandedTaskId = nil
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .bold : .regular))
                                .foregroundColor(selectedTab == tab ? PeezyTheme.Colors.deepInk : .gray)

                            let count = taskCount(for: tab)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(selectedTab == tab ? PeezyTheme.Colors.deepInk : .gray)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(selectedTab == tab
                                                  ? PeezyTheme.Colors.deepInk.opacity(0.1)
                                                  : Color.gray.opacity(0.1))
                                    )
                            }
                        }

                        // Underline indicator
                        Rectangle()
                            .fill(selectedTab == tab ? PeezyTheme.Colors.deepInk : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                switch selectedTab {
                case .todo:
                    if allUpcomingTasks.isEmpty {
                        tabEmptyState(message: "All caught up!")
                    } else {
                        ForEach(allUpcomingTasks) { task in
                            TaskListRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                onExpand: { toggleExpand(task.id) },
                                onStart: onNavigateToTask != nil ? { onNavigateToTask?(task) } : nil
                            )
                        }
                    }

                case .inProgress:
                    if userInProgressTasks.isEmpty && inProgressTasks.isEmpty {
                        tabEmptyState(message: "No tasks in progress")
                    } else {
                        if !userInProgressTasks.isEmpty {
                            subsectionHeader(title: "You're on it")
                            ForEach(userInProgressTasks) { task in
                                TaskListRow(
                                    task: task,
                                    isExpanded: expandedTaskId == task.id,
                                    onExpand: { toggleExpand(task.id) },
                                    onStart: nil
                                )
                            }
                        }
                        if !inProgressTasks.isEmpty {
                            subsectionHeader(title: "Peezy is on it")
                            ForEach(inProgressTasks) { task in
                                TaskListRow(
                                    task: task,
                                    isExpanded: expandedTaskId == task.id,
                                    onExpand: { toggleExpand(task.id) },
                                    onStart: nil
                                )
                            }
                        }
                    }

                case .later:
                    if snoozedTasks.isEmpty {
                        tabEmptyState(message: "Nothing snoozed")
                    } else {
                        ForEach(snoozedTasks) { task in
                            TaskListRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                onExpand: { toggleExpand(task.id) },
                                onStart: onNavigateToTask != nil ? { onNavigateToTask?(task) } : nil
                            )
                        }
                    }

                case .done:
                    if completedTasks.isEmpty {
                        tabEmptyState(message: "No completed tasks yet")
                    } else {
                        ForEach(completedTasks) { task in
                            TaskListRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                onExpand: { toggleExpand(task.id) },
                                onStart: nil
                            )
                        }
                    }
                }

                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            await loadTasks()
        }
    }

    // MARK: - Subsection Header

    private func subsectionHeader(title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Tab Empty State

    private func tabEmptyState(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(PeezyTheme.Colors.deepInk.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    // MARK: - Helpers

    private func toggleExpand(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            expandedTaskId = expandedTaskId == id ? nil : id
        }
    }

    // MARK: - Empty State (no tasks at all)

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 50))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))

            Text("No tasks yet")
                .font(.title3.bold())
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Text("Tasks will appear here after your assessment.")
                .font(.subheadline)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Data Loading

    private func loadTasks() async {
        let showSpinner = allTasks.isEmpty
        if showSpinner { isLoading = true }

        do {
            let service = TimelineService()
            let tasks = try await service.fetchUserTasks()
            await MainActor.run {
                self.allTasks = tasks
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.allTasks = viewModel?.cards.filter {
                    $0.type == .task || $0.type == .vendor
                } ?? []
                self.isLoading = false
            }
        }
    }
}

// MARK: - Task List Row

struct TaskListRow: View {
    let task: PeezyCard
    var isExpanded: Bool = false
    var onExpand: () -> Void = {}
    var onStart: (() -> Void)?

    private var isSnoozed: Bool {
        if task.status == .snoozed { return true }
        if let snoozedUntil = task.snoozedUntil, snoozedUntil > DateProvider.shared.now {
            return true
        }
        return false
    }

    private var isCompleted: Bool {
        task.status == .completed
    }

    private var isInProgress: Bool {
        task.status == .inProgress
    }

    private var isUserInProgress: Bool {
        task.status == .userInProgress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(PeezyTheme.Colors.deepInk.opacity(0.05))
                        .frame(width: 48, height: 48)
                    Image(systemName: iconForCategory(task.taskCategory))
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(isCompleted ? .gray : PeezyTheme.Colors.deepInk.opacity(0.8))
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(task.title)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(isCompleted ? .gray : PeezyTheme.Colors.deepInk)
                            .strikethrough(isCompleted, color: .gray)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.gray.opacity(0.4))
                            .rotationEffect(.degrees(isExpanded ? -180 : 0))
                            .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0), value: isExpanded)
                            .padding(.top, 4)
                    }

                    if !task.subtitle.isEmpty {
                        Text(task.subtitle)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.gray.opacity(0.9))
                            .lineSpacing(4)
                            .lineLimit(isExpanded ? nil : 2)
                    }

                    // Status badge for non-upcoming tasks
                    if isUserInProgress || isInProgress || isSnoozed {
                        HStack {
                            if isUserInProgress {
                                Text("You're on it")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.cyan)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.cyan.opacity(0.1))
                                    .clipShape(Capsule())
                            } else if isInProgress {
                                Text("Peezy is on it")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            } else if isSnoozed {
                                Text("Snoozed")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)) {
                    onExpand()
                }
            }

            // Start button — expanded state only
            if isExpanded {
                // Start button (hide for Completed, InProgress, and UserInProgress tasks)
                if !isCompleted && !isInProgress && !isUserInProgress, let onStart {
                    Button(action: onStart) {
                        Text("Start Task")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(PeezyTheme.Colors.deepInk)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: PeezyTheme.Colors.deepInk.opacity(0.04), radius: 12, x: 0, y: 6)
        .opacity(isCompleted ? 0.6 : 1.0)
        .padding(.vertical, 8)
    }

    // MARK: - Category Icon

    private func iconForCategory(_ category: String?) -> String {
        switch (category ?? "").lowercased() {
        case "moving":          return "shippingbox.fill"
        case "packing":         return "archivebox.fill"
        case "services":        return "wrench.and.screwdriver.fill"
        case "utilities":       return "bolt.fill"
        case "administrative":  return "doc.text.fill"
        case "children":        return "figure.and.child.holdinghands"
        case "pets":            return "pawprint.fill"
        case "finance":         return "creditcard.fill"
        case "insurance":       return "shield.checkered"
        case "health":          return "heart.fill"
        case "fitness":         return "figure.run"
        default:                return "checklist"
        }
    }
}

// MARK: - Preview

#Preview {
    PeezyTaskStream(previewTasks: [
        // Active tasks
        PeezyCard(
            id: "1",
            type: .task,
            title: "Book Professional Movers",
            subtitle: "Research and reserve a moving company. Get at least three quotes from licensed, insured movers and compare pricing, availability, and reviews.",
            priority: .high,
            status: .upcoming,
            dueDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
            taskCategory: "moving"
        ),
        PeezyCard(
            id: "2",
            type: .task,
            title: "Set Up Mail Forwarding",
            subtitle: "Visit USPS.com or your local post office to forward mail from your current address to your new one.",
            priority: .normal,
            status: .upcoming,
            dueDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
            taskCategory: "administrative"
        ),
        // User in progress
        PeezyCard(
            id: "3a",
            type: .task,
            title: "Pack Kitchen Items",
            subtitle: "Wrap dishes, glasses, and small appliances. Use plenty of padding.",
            priority: .normal,
            status: .userInProgress,
            taskCategory: "packing",
            userInProgressDate: Date(),
            userInProgressReturnDate: Calendar.current.date(byAdding: .day, value: 3, to: Date())
        ),
        // Peezy in progress
        PeezyCard(
            id: "3",
            type: .task,
            title: "Transfer Utilities",
            subtitle: "Contact your electric, gas, water, and internet providers.",
            priority: .urgent,
            status: .inProgress,
            dueDate: Date(),
            taskCategory: "utilities"
        ),
        // Snoozed task
        PeezyCard(
            id: "5",
            type: .task,
            title: "Hire a Cleaning Service",
            subtitle: "Schedule a deep clean of your old place before move-out.",
            priority: .normal,
            status: .snoozed,
            snoozedUntil: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            taskCategory: "services"
        ),
        // Completed tasks
        PeezyCard(
            id: "6",
            type: .task,
            title: "Declutter & Donate",
            subtitle: "Go room by room and sort items into keep, donate, and discard piles.",
            priority: .normal,
            status: .completed,
            taskCategory: "packing"
        ),
        PeezyCard(
            id: "7",
            type: .task,
            title: "Gather Packing Supplies",
            subtitle: "Stock up on boxes, tape, bubble wrap, and markers.",
            priority: .low,
            status: .completed,
            taskCategory: "packing"
        )
    ])
}
