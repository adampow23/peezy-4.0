import SwiftUI

struct TasksList: View {
    let selectedTab: TaskTab
    let groups: TaskGrouping.Groups
    @Binding var expandedTaskId: String?
    let onAction: (TaskAction) -> Void
    /// S4-CD3: the shared surface state per row; nil keeps the committed rows.
    var surfaceState: ((PeezyCard) -> TaskDispositionSurfaceState)? = nil
    /// C9.3.14: the one shared urgent-recovery projection (`TasksStore.urgentRecoveryLines`) and the line's route handler.
    var urgentRecoveryLines: [UrgentRecoveryLine] = []
    var onOpenUrgent: ((UrgentRecoveryLine) -> Void)? = nil

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
            UrgentRecoveryGroupView(lines: urgentRecoveryLines) { line in onOpenUrgent?(line) }
            if groups.todoDisplay.isEmpty {
                TasksTabEmptyState(message: "You're on track. New tasks drop in daily.")
            } else {
                ForEach(groups.todoDisplay) { task in
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
        // The .id(rowIdentity) workaround for the old id-only PeezyCard
        // Equatable is gone (Spec 04 Phase C) — memberwise == (Spec 03 Phase A)
        // repaints rows on field changes without forced re-identity.
        TaskRow(
            task: task,
            section: section,
            isExpanded: expandedTaskId == task.id,
            onExpandToggle: { toggle(task.id) },
            onAction: onAction,
            surfaceState: surfaceState?(task)
        )
    }

    private func toggle(_ id: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            expandedTaskId = (expandedTaskId == id) ? nil : id
        }
    }
}

/// The C9.3.14 "Needs attention now" group: hidden at zero lines, the task's own header at one, the group header at many;
/// one line per task carrying the policy threshold label and the line's route. Home and Tasks render this one view over
/// the one shared projection.
struct UrgentRecoveryGroupView: View {
    let lines: [UrgentRecoveryLine]
    let onOpen: (UrgentRecoveryLine) -> Void

    static func actionLabel(for route: UrgentRecoveryLine.Route) -> String {
        switch route {
        case .row: return "Open task"
        case .outcome: return "Record outcome"
        }
    }

    var body: some View {
        if let header = UrgentRecoveryProjection.header(for: lines) {
            VStack(alignment: .leading, spacing: 8) {
                TasksSectionHeader(title: header)
                ForEach(lines) { line in
                    Button { onOpen(line) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.title)
                                .font(PeezyTheme.Typography.captionMedium)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.85))
                            Text("\(line.thresholdId) · \(Self.actionLabel(for: line.route))")
                                .font(PeezyTheme.Typography.caption)
                                .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PeezyTheme.Colors.deepInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("urgentRecovery.\(line.taskDocumentId)")
                }
            }
            .padding(.bottom, 8)
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
