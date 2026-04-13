//
//  PeezyTimelineView.swift
//  Peezy
//
//  Tabbed task list: To-Do | In Progress | Done
//  Snoozed tasks appear at bottom of To-Do with "Snoozed" badge.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Tab Enum

enum TaskTab: String, CaseIterable {
    case todo = "To-Do"
    case inProgress = "In Progress"
    case done = "Done"
}

// MARK: - Main View

struct PeezyTaskStream: View {
    var viewModel: PeezyStackViewModel?
    var userState: UserState?

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    var onNavigateToTask: ((PeezyCard) -> Void)?
    var onNavigateHome: (() -> Void)?

    @State private var allTasks: [PeezyCard] = []
    @State private var isLoading = true
    @State private var expandedTaskId: String? = nil
    @State private var showConfetti = false
    @State private var selectedTab: TaskTab = .todo

    private var previewTasks: [PeezyCard]?

    init() {
        self.viewModel = nil
        self.userState = nil
        self.onNavigateToTask = nil
        self.onNavigateHome = nil
        self.previewTasks = nil
    }

    init(viewModel: PeezyStackViewModel?, userState: UserState?, onNavigateToTask: ((PeezyCard) -> Void)? = nil, onNavigateHome: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.userState = userState
        self.onNavigateToTask = onNavigateToTask
        self.onNavigateHome = onNavigateHome
        self.previewTasks = nil
    }

    init(previewTasks: [PeezyCard]) {
        self.viewModel = nil
        self.userState = nil
        self.onNavigateToTask = nil
        self.onNavigateHome = nil
        self.previewTasks = previewTasks
    }

    // MARK: - Grouped Tasks

    /// To-Do: upcoming tasks (sorted by urgency) + snoozed tasks at the bottom
    private var todoTasks: [PeezyCard] {
        let upcoming = allTasks.filter { card in
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

        let snoozed = allTasks.filter { isSnoozed($0) }
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }

        return upcoming + snoozed
    }

    /// "You're on it" — status = UserInProgress
    private var userInProgressTasks: [PeezyCard] {
        allTasks.filter { $0.status == .userInProgress }
            .sorted { ($0.userInProgressReturnDate ?? .distantFuture) < ($1.userInProgressReturnDate ?? .distantFuture) }
    }

    /// "Peezy is on it" — status = InProgress
    private var inProgressTasks: [PeezyCard] {
        allTasks.filter { $0.status == .inProgress }
            .sorted { a, b in
                if a.priority.rawValue != b.priority.rawValue {
                    return a.priority.rawValue > b.priority.rawValue
                }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    /// Completed tasks
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
        case .todo:       return todoTasks.count
        case .inProgress: return userInProgressTasks.count + inProgressTasks.count
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

            if showConfetti {
                ConfettiView(isActive: $showConfetti, intensity: .high)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
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

    private var headerTitle: String {
        if let name = userState?.name, !name.isEmpty {
            let firstName = name.split(separator: " ").first.map(String.init) ?? name
            return "\(firstName)'s Task List"
        }
        return "Task List"
    }

    private var headerView: some View {
        HStack {
            Text(headerTitle)
                .font(PeezyTheme.Typography.title2)
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Spacer()

            if let onNavigateHome {
                Button {
                    onNavigateHome()
                } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial.opacity(0.8))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                Button {
                    PeezyHaptics.light()
                    withAnimation(PeezyTheme.Animation.easeOut) {
                        selectedTab = tab
                        expandedTaskId = nil
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 5) {
                            Text(tab.rawValue)
                                .font(selectedTab == tab ? PeezyTheme.Typography.footnoteMedium : PeezyTheme.Typography.footnote)
                                .foregroundStyle(selectedTab == tab ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.4))

                            let count = taskCount(for: tab)
                            if count > 0 {
                                Text("\(count)")
                                    .font(PeezyTheme.Typography.captionMedium)
                                    .foregroundStyle(selectedTab == tab ? PeezyTheme.Colors.deepInk : PeezyTheme.Colors.deepInk.opacity(0.4))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(PeezyTheme.Colors.deepInk.opacity(selectedTab == tab ? 0.1 : 0.05))
                                    )
                            }
                        }

                        Rectangle()
                            .fill(selectedTab == tab ? PeezyTheme.Colors.deepInk : Color.clear)
                            .frame(height: 2)
                            .clipShape(.rect(cornerRadius: 1))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("timeline_tab_\(tab.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Divider().background(PeezyTheme.Colors.deepInk.opacity(0.06))
        }
    }

    // MARK: - Tab Content

    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                switch selectedTab {
                case .todo:
                    if todoTasks.isEmpty {
                        tabEmptyState(message: "You're on track. New tasks drop in daily.")
                    } else {
                        ForEach(todoTasks) { task in
                            TaskListRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                onExpand: { toggleExpand(task.id) },
                                onStart: onStartHandler(for: task),
                                onComplete: nil
                            )
                        }
                    }

                case .inProgress:
                    if userInProgressTasks.isEmpty && inProgressTasks.isEmpty {
                        tabEmptyState(message: "Nothing in the works yet.")
                    } else {
                        if !userInProgressTasks.isEmpty {
                            subsectionHeader(title: "You're on it")
                            ForEach(userInProgressTasks) { task in
                                TaskListRow(
                                    task: task,
                                    isExpanded: expandedTaskId == task.id,
                                    onExpand: { toggleExpand(task.id) },
                                    onStart: nil,
                                    onComplete: {
                                        markTaskComplete(task)
                                    }
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
                                    onStart: nil,
                                    onComplete: nil
                                )
                            }
                        }
                    }

                case .done:
                    if completedTasks.isEmpty {
                        tabEmptyState(message: "Completed tasks will stack up here.")
                    } else {
                        ForEach(completedTasks) { task in
                            TaskListRow(
                                task: task,
                                isExpanded: expandedTaskId == task.id,
                                onExpand: { toggleExpand(task.id) },
                                onStart: nil,
                                onComplete: nil,
                                onUndo: { undoTaskCompletion(task) }
                            )
                        }
                    }
                }

                Color.clear.frame(height: 100)
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
                .font(PeezyTheme.Typography.captionMedium)
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Tab Empty State

    private func tabEmptyState(message: String) -> some View {
        Text(message)
            .font(PeezyTheme.Typography.callout)
            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    // MARK: - Helpers

    private func onStartHandler(for task: PeezyCard) -> (() -> Void)? {
        guard onNavigateToTask != nil else { return nil }
        return { onNavigateToTask?(task) }
    }

    private func toggleExpand(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            expandedTaskId = expandedTaskId == id ? nil : id
        }
    }

    // MARK: - Mark Task Complete

    private func markTaskComplete(_ task: PeezyCard) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        showConfetti = true
        Task {
            try? await Task.sleep(for: .seconds(3.0))
            showConfetti = false
        }

        let db = Firestore.firestore()
        let taskRef = db.collection("users").document(userId).collection("tasks").document(task.id)

        taskRef.updateData([
            "status": "Completed",
            "completedAt": FieldValue.serverTimestamp()
        ]) { error in
            if error == nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if let index = allTasks.firstIndex(where: { $0.id == task.id }) {
                        allTasks[index].status = .completed
                        expandedTaskId = nil
                    }
                }
            }
        }
    }

    private func undoTaskCompletion(_ task: PeezyCard) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        let taskRef = db.collection("users").document(userId).collection("tasks").document(task.id)

        taskRef.updateData([
            "status": "Upcoming",
            "completedAt": FieldValue.delete()
        ]) { error in
            if error == nil {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if let index = allTasks.firstIndex(where: { $0.id == task.id }) {
                        allTasks[index].status = .upcoming
                        expandedTaskId = nil
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 50))
                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))

            Text("No tasks yet")
                .font(PeezyTheme.Typography.headline)
                .foregroundStyle(PeezyTheme.Colors.deepInk)

            Text("Tasks will appear here after your assessment.")
                .font(PeezyTheme.Typography.callout)
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
    var onComplete: (() -> Void)?
    var onUndo: (() -> Void)?

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
                        .foregroundStyle(isCompleted ? PeezyTheme.Colors.deepInk.opacity(0.3) : PeezyTheme.Colors.deepInk.opacity(0.7))
                }
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(task.title)
                            .font(PeezyTheme.Typography.bodyMedium)
                            .foregroundStyle(isCompleted ? PeezyTheme.Colors.deepInk.opacity(0.4) : PeezyTheme.Colors.deepInk)
                            .strikethrough(isCompleted, color: PeezyTheme.Colors.deepInk.opacity(0.3))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(PeezyTheme.Typography.captionMedium)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.3))
                            .rotationEffect(.degrees(isExpanded ? -180 : 0))
                            .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0), value: isExpanded)
                            .padding(.top, 4)
                    }

                    if !task.subtitle.isEmpty && !isCompleted {
                        Text(task.subtitle)
                            .font(PeezyTheme.Typography.callout)
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .lineSpacing(4)
                            .lineLimit(isExpanded ? nil : 2)
                    }

                    // Status badges
                    if isUserInProgress || isInProgress || isSnoozed {
                        HStack {
                            if isUserInProgress {
                                Text("You're on it")
                                    .font(PeezyTheme.Typography.captionMedium)
                                    .foregroundStyle(PeezyTheme.Colors.infoBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(PeezyTheme.Colors.infoBlue.opacity(0.1))
                                    .clipShape(Capsule())
                            } else if isInProgress {
                                Text("Peezy is on it")
                                    .font(PeezyTheme.Typography.captionMedium)
                                    .foregroundStyle(PeezyTheme.Colors.accentBlue)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(PeezyTheme.Colors.accentBlue.opacity(0.1))
                                    .clipShape(Capsule())
                            } else if isSnoozed {
                                Text("Snoozed")
                                    .font(PeezyTheme.Typography.captionMedium)
                                    .foregroundStyle(PeezyTheme.Colors.warningOrange)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(PeezyTheme.Colors.warningOrange.opacity(0.1))
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
                PeezyHaptics.light()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    onExpand()
                }
            }

            // Expanded buttons
            if isExpanded {
                if !isCompleted && !isInProgress && !isUserInProgress, let onStart {
                    PeezyAssessmentButton("Start task") {
                        onStart()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isUserInProgress, let onComplete {
                    PeezyAssessmentButton("Mark as completed") {
                        PeezyHaptics.medium()
                        onComplete()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Undo — same button style as other actions
                if isCompleted, let onUndo {
                    PeezyAssessmentButton("Undo completion") {
                        PeezyHaptics.light()
                        onUndo()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                    .fill(Color.white.opacity(0.15))
            }
            .overlay(
                RoundedRectangle(cornerRadius: PeezyTheme.Layout.cornerRadiusLarge, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
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
        PeezyCard(
            id: "1", type: .task,
            title: "Book Professional Movers",
            subtitle: "Research and reserve a moving company.",
            priority: .high, status: .upcoming,
            dueDate: Calendar.current.date(byAdding: .day, value: 5, to: Date()),
            taskCategory: "moving"
        ),
        PeezyCard(
            id: "2", type: .task,
            title: "Set Up Mail Forwarding",
            subtitle: "Forward mail from your current address to your new one.",
            priority: .normal, status: .upcoming,
            taskCategory: "administrative"
        ),
        PeezyCard(
            id: "3", type: .task,
            title: "Transfer Utilities",
            subtitle: "Contact your electric, gas, water, and internet providers.",
            priority: .urgent, status: .inProgress,
            taskCategory: "utilities"
        ),
        PeezyCard(
            id: "4", type: .task,
            title: "Hire a Cleaning Service",
            subtitle: "Schedule a deep clean of your old place.",
            priority: .normal, status: .snoozed,
            snoozedUntil: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            taskCategory: "services"
        ),
        PeezyCard(
            id: "5", type: .task,
            title: "Declutter & Donate",
            subtitle: "Sort items into keep, donate, and discard piles.",
            priority: .normal, status: .completed,
            taskCategory: "packing"
        )
    ])
}
