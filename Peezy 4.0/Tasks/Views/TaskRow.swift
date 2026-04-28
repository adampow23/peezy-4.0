import SwiftUI

enum TaskSection {
    case todo, userInProgress, peezyOnIt, done
}

struct TaskRow: View {
    let task: PeezyCard
    let section: TaskSection
    let isExpanded: Bool
    let onExpandToggle: () -> Void
    let onAction: (TaskAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskRowHeader(
                task: task,
                isExpanded: isExpanded,
                section: section,
                onTap: onExpandToggle
            )

            if isExpanded {
                TaskRowButtons(
                    layout: TaskRowButtons.layout(for: task, section: section),
                    onAction: onAction
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(rowBackground)
        .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)
        .opacity(section == .done ? 0.7 : 1.0)
        .padding(.vertical, 8)
    }

    private var rowBackground: some View {
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
    }
}

#Preview("TaskRow — samples") {
    ScrollView {
        VStack(spacing: 0) {
            TaskRow(
                task: PeezyCard(
                    id: "1", type: .task,
                    title: "Book Professional Movers",
                    subtitle: "Research and reserve a moving company.",
                    priority: .high, status: .upcoming,
                    taskCategory: "moving"
                ),
                section: .todo,
                isExpanded: true,
                onExpandToggle: {},
                onAction: { _ in }
            )

            TaskRow(
                task: PeezyCard(
                    id: "2", type: .task,
                    title: "Scan your home",
                    subtitle: "Walk through each room so we can build your inventory.",
                    workflowId: "scan_inventory",
                    priority: .high, status: .userInProgress,
                    actionType: "in-app-inventory"
                ),
                section: .userInProgress,
                isExpanded: true,
                onExpandToggle: {},
                onAction: { _ in }
            )

            TaskRow(
                task: PeezyCard(
                    id: "3", type: .task,
                    title: "Declutter & Donate",
                    subtitle: "Sort items into keep, donate, discard.",
                    priority: .normal, status: .completed,
                    taskCategory: "packing"
                ),
                section: .done,
                isExpanded: true,
                onExpandToggle: {},
                onAction: { _ in }
            )
        }
        .padding(.horizontal, 16)
    }
}
