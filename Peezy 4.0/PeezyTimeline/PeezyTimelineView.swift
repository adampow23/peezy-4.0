//
//  PeezyTimelineView.swift
//  Peezy
//
//  Simple grouped task list: Active → Snoozed → Completed
//  Data source: TimelineService (unchanged)
//

import SwiftUI

// MARK: - Task Tab

enum TaskTab: String, CaseIterable {
    case active = "Active"
    case snoozed = "Snoozed"
    case completed = "Completed"
}

// MARK: - Main View

struct PeezyTaskStream: View {
    // External data (kept for container compatibility)
    var viewModel: PeezyStackViewModel?
    var userState: UserState?

    // Task data from Firestore
    @State private var allTasks: [PeezyCard] = []
    @State private var isLoading = true

    // Tab selection
    @State private var selectedTab: TaskTab = .active

    // Expandable row tracking
    @State private var expandedTaskId: String? = nil

    // Preview/test data injection
    private var previewTasks: [PeezyCard]?

    // Init for standalone use (preview/testing)
    init() {
        self.viewModel = nil
        self.userState = nil
        self.previewTasks = nil
    }

    // Init for integrated use
    init(viewModel: PeezyStackViewModel?, userState: UserState?) {
        self.viewModel = viewModel
        self.userState = userState
        self.previewTasks = nil
    }

    // Init with sample data for previews
    init(previewTasks: [PeezyCard]) {
        self.viewModel = nil
        self.userState = nil
        self.previewTasks = previewTasks
    }

    // MARK: - Grouped Tasks

    private var activeTasks: [PeezyCard] {
        allTasks.filter { card in
            card.status != .completed && card.status != .skipped && !isSnoozed(card)
        }
        .sorted { a, b in
            if a.priority.rawValue != b.priority.rawValue {
                return a.priority.rawValue > b.priority.rawValue
            }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
    }

    private var snoozedTasks: [PeezyCard] {
        allTasks.filter { isSnoozed($0) }
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }
    }

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

    // MARK: - Filtered Tasks

    private var tasksForSelectedTab: [PeezyCard] {
        switch selectedTab {
        case .active: return activeTasks
        case .snoozed: return snoozedTasks
        case .completed: return completedTasks
        }
    }

    private func countForTab(_ tab: TaskTab) -> Int {
        switch tab {
        case .active: return activeTasks.count
        case .snoozed: return snoozedTasks.count
        case .completed: return completedTasks.count
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {
                headerView
                tabBar

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                    Spacer()
                } else if allTasks.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    taskList
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Task List")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text(taskSummary)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

            Spacer()

            if let daysLeft = userState?.daysUntilMove, daysLeft > 0 {
                Text("\(daysLeft)d")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 16)
    }

    private var taskSummary: String {
        let active = activeTasks.count
        let snoozed = snoozedTasks.count
        let completed = completedTasks.count

        if active == 0 && snoozed == 0 {
            return completed > 0 ? "\(completed) completed" : "No tasks yet"
        }

        var parts: [String] = []
        if active > 0 { parts.append("\(active) active") }
        if snoozed > 0 { parts.append("\(snoozed) snoozed") }
        if completed > 0 { parts.append("\(completed) done") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(TaskTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                let count = countForTab(tab)

                Button {
                    PeezyHaptics.light()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selectedTab = tab
                        expandedTaskId = nil
                    }
                } label: {
                    Text("\(tab.rawValue) (\(count))")
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white.opacity(0.12))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.17).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Task List

    private var taskList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                let tasks = tasksForSelectedTab

                if tasks.isEmpty {
                    tabEmptyState
                } else {
                    ForEach(tasks) { task in
                        TaskListRow(
                            task: task,
                            isExpanded: expandedTaskId == task.id,
                            onExpand: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    expandedTaskId = expandedTaskId == task.id ? nil : task.id
                                }
                            }
                        )
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 50))
                .foregroundStyle(.white.opacity(0.4))

            Text("No tasks yet")
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text("Tasks will appear here after your assessment.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    private var tabEmptyState: some View {
        VStack(spacing: 12) {
            let (icon, message): (String, String) = {
                switch selectedTab {
                case .active:
                    return ("checkmark.seal.fill", "No active tasks — you're all caught up!")
                case .snoozed:
                    return ("moon.zzz.fill", "No snoozed tasks")
                case .completed:
                    return ("trophy.fill", "No completed tasks yet")
                }
            }()

            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.3))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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

    private let charcoalColor = Color(red: 0.15, green: 0.15, blue: 0.17)

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

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 14) {
                HStack(spacing: 14) {
                    statusIcon
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .strikethrough(isCompleted)
                            .lineLimit(1)

                        if isSnoozed, let snoozedUntil = task.snoozedUntil {
                            Text("Until \(formattedDate(snoozedUntil))")
                                .font(.caption)
                                .foregroundColor(.orange.opacity(0.8))
                        }

                        if isInProgress {
                            Text("In Progress · Getting quotes...")
                                .font(.caption)
                                .foregroundColor(.cyan.opacity(0.8))
                        }
                    }

                    Spacer()
                }

                // Expand/collapse chevron (visual affordance only)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white.opacity(0.3))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                    .frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)

            // Expanded description
            if isExpanded, !task.subtitle.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                Text(task.subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(rowBackground)
        .opacity(isCompleted ? 0.5 : (isSnoozed ? 0.7 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.vertical, 4)
    }

    // MARK: - Category Icon

    @ViewBuilder
    private var statusIcon: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
        } else if isSnoozed {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 18))
                .foregroundColor(.yellow)
        } else if isInProgress {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.cyan)
        } else {
            Image(systemName: iconForCategory(task.taskCategory))
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.5))
        }
    }

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
        default:                return "list.bullet.circle.fill"
        }
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(charcoalColor.opacity(isCompleted ? 0.3 : 0.5))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private var borderColor: Color {
        if isInProgress { return .cyan.opacity(0.25) }
        if isSnoozed { return .yellow.opacity(0.15) }
        if task.priority == .urgent { return .orange.opacity(0.2) }
        return .white.opacity(0.06)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
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
            subtitle: "Visit USPS.com or your local post office to forward mail from your current address to your new one. This ensures you don't miss important documents during the transition.",
            priority: .normal,
            status: .upcoming,
            dueDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()),
            taskCategory: "administrative"
        ),
        PeezyCard(
            id: "3",
            type: .task,
            title: "Transfer Utilities",
            subtitle: "Contact your electric, gas, water, and internet providers to schedule disconnection at your old address and activation at your new one.",
            priority: .urgent,
            status: .inProgress,
            dueDate: Date(),
            taskCategory: "utilities"
        ),
        PeezyCard(
            id: "4",
            type: .task,
            title: "Update Vehicle Registration",
            subtitle: "Visit your local DMV or go online to update your vehicle registration and driver's license with your new address.",
            priority: .normal,
            status: .upcoming,
            taskCategory: "administrative"
        ),
        // Snoozed task
        PeezyCard(
            id: "5",
            type: .task,
            title: "Hire a Cleaning Service",
            subtitle: "Schedule a deep clean of your old place before move-out to ensure you get your security deposit back.",
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
            subtitle: "Go room by room and sort items into keep, donate, and discard piles. Schedule a donation pickup or drop-off.",
            priority: .normal,
            status: .completed,
            taskCategory: "packing"
        ),
        PeezyCard(
            id: "7",
            type: .task,
            title: "Gather Packing Supplies",
            subtitle: "Stock up on boxes, tape, bubble wrap, and markers. Check local stores or community groups for free moving boxes.",
            priority: .low,
            status: .completed,
            taskCategory: "packing"
        )
    ])
}
