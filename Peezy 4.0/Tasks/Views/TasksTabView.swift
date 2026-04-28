import SwiftUI

struct TasksTabView: View {
    @Environment(TasksStore.self) private var store

    var userState: UserState?
    var onNavigateToTask: ((PeezyCard) -> Void)?
    var onNavigateHome: (() -> Void)?

    @State private var selectedTab: TaskTab = .todo
    @State private var expandedTaskId: String?
    @State private var pendingConfirm: PendingConfirmation?

    private var isResetting: Bool {
        !store.pendingResetTaskIds.isEmpty
    }

    var body: some View {
        let groups = TaskGrouping.partition(store.tasks)

        ZStack {
            InteractiveBackground()

            VStack(spacing: 0) {
                TasksHeader(
                    userName: userState?.name,
                    onNavigateHome: onNavigateHome
                )

                content(groups: groups)
            }

            TasksOverlayLayer(isResetting: isResetting)
        }
        .confirmationDialog(
            pendingConfirm?.title ?? "",
            isPresented: Binding(
                get: { pendingConfirm != nil },
                set: { if !$0 { pendingConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirm
        ) { pending in
            Button(pending.confirmLabel, role: .destructive) {
                performConfirmed(pending)
                pendingConfirm = nil
            }
            Button(pending.cancelLabel, role: .cancel) {
                pendingConfirm = nil
            }
        } message: { pending in
            Text(pending.message)
        }
        .onChange(of: store.tasks) { _, newTasks in
            if let pc = pendingConfirm {
                switch pc {
                case .resetInventory(let card):
                    if !newTasks.contains(where: { $0.id == card.id }) {
                        pendingConfirm = nil
                    }
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    @ViewBuilder
    private func content(groups: TaskGrouping.Groups) -> some View {
        switch store.loadState {
        case .loading where store.tasks.isEmpty:
            Spacer()
            ProgressView().tint(PeezyTheme.Colors.deepInk)
            Spacer()
        case .failed(let msg):
            TasksErrorBanner(message: msg) {
                if let uid = userState?.userId { store.start(userId: uid) }
            }
        default:
            if store.tasks.isEmpty {
                Spacer()
                TasksEmptyState()
                Spacer()
            } else {
                TasksTabBar(
                    selectedTab: $selectedTab,
                    counts: tabCounts(groups: groups)
                )
                .onChange(of: selectedTab) { _, _ in
                    expandedTaskId = nil
                }

                TasksList(
                    selectedTab: selectedTab,
                    groups: groups,
                    expandedTaskId: $expandedTaskId,
                    onAction: handleAction
                )
            }
        }
    }

    private func tabCounts(groups: TaskGrouping.Groups) -> [TaskTab: Int] {
        [
            .todo: groups.todo.count,
            .inProgress: groups.userInProgress.count + groups.peezyOnIt.count,
            .done: groups.completed.count
        ]
    }

    private func handleAction(_ action: TaskAction) {
        switch action {
        case .resetInventory(let card):
            pendingConfirm = .resetInventory(card)
        default:
            Task { @MainActor in
                await store.dispatch(action) { card in
                    onNavigateToTask?(card)
                }
            }
        }
    }

    private func performConfirmed(_ pending: PendingConfirmation) {
        if case .resetInventory(let card) = pending {
            Task { @MainActor in
                await store.dispatch(.resetInventory(card)) { _ in }
            }
        }
    }
}
