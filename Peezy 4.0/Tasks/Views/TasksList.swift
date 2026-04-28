import SwiftUI

struct TasksList: View {
    let selectedTab: TaskTab
    let groups: TaskGrouping.Groups
    @Binding var expandedTaskId: String?
    let onAction: (TaskAction) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                content

                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
        }
        .refreshable {
            try? await Task.sleep(for: .milliseconds(400))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .todo:
            if groups.todo.isEmpty {
                TasksTabEmptyState(message: "You're on track. New tasks drop in daily.")
            } else {
                ForEach(groups.todo) { task in
                    row(task: task, section: .todo)
                }
            }

        case .inProgress:
            if groups.userInProgress.isEmpty && groups.peezyOnIt.isEmpty {
                TasksTabEmptyState(message: "Nothing in the works yet.")
            } else {
                if !groups.userInProgress.isEmpty {
                    TasksSectionHeader(title: "You're on it")
                    ForEach(groups.userInProgress) { task in
                        row(task: task, section: .userInProgress)
                    }
                }
                if !groups.peezyOnIt.isEmpty {
                    TasksSectionHeader(title: "Peezy is on it")
                    ForEach(groups.peezyOnIt) { task in
                        row(task: task, section: .peezyOnIt)
                    }
                }
            }

        case .done:
            if groups.completed.isEmpty {
                TasksTabEmptyState(message: "Completed tasks will stack up here.")
            } else {
                ForEach(groups.completed) { task in
                    row(task: task, section: .done)
                }
            }
        }
    }

    private func row(task: PeezyCard, section: TaskSection) -> some View {
        TaskRow(
            task: task,
            section: section,
            isExpanded: expandedTaskId == task.id,
            onExpandToggle: { toggle(task.id) },
            onAction: onAction
        )
        .id(rowIdentity(task: task, section: section))
    }

    private func rowIdentity(task: PeezyCard, section: TaskSection) -> String {
        "\(task.id)-\(String(describing: section))-\(String(describing: task.status))"
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            expandedTaskId = (expandedTaskId == id) ? nil : id
        }
    }
}

struct TasksSectionHeader: View {
    let title: String

    var body: some View {
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
}
