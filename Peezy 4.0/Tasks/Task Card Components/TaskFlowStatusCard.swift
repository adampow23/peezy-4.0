//
//  TaskFlowStatusCard.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/12/26.
//

import SwiftUI

// MARK: - Task Flow Status Card
// Final card for self-service flows. Asks the user what they're doing about the task.
// Three hardcoded options — each triggers a different action. Tap dismisses the flow.
// Wraps TaskFlowTilesCard for pixel-perfect visual consistency with all other tiles.
//
// No SummaryCard after this. The StatusCard IS the ending for self-service tasks.
//
// Updated Type 1 sequence:
//   TitleCard → InfoCard ("Good to Know") → StatusCard

struct TaskFlowStatusCard: View {
    let taskTitle: String
    var question: String = "What's the plan with this?"
    var showBack: Bool = false
    let onLater: () -> Void
    let onInProgress: () -> Void
    let onDone: () -> Void
    var onBack: (() -> Void)? = nil

    var body: some View {
        TaskFlowTilesCard(
            taskTitle: taskTitle,
            question: question,
            options: [
                FlowOption(id: "later", label: "Later", icon: "clock"),
                FlowOption(id: "in_progress", label: "Mark as in progress", icon: "arrow.forward.circle"),
                FlowOption(id: "done", label: "Already done", icon: "checkmark.circle")
            ],
            mode: .single,
            selectedIds: [],
            showBack: showBack,
            onSelect: { id in
                switch id {
                case "later": onLater()
                case "in_progress": onInProgress()
                case "done": onDone()
                default: break
                }
            },
            onBack: onBack
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Status — Return Keys") {
    TaskFlowStatusCard(
        taskTitle: "Return all access devices",
        showBack: true,
        onLater: { print("Later") },
        onInProgress: { print("In Progress") },
        onDone: { print("Done") },
        onBack: { print("Back") }
    )
    .peezyCardChrome()
}

#Preview("Status — Buy Packing Supplies") {
    TaskFlowStatusCard(
        taskTitle: "Buy packing supplies",
        onLater: { print("Later") },
        onInProgress: { print("In Progress") },
        onDone: { print("Done") }
    )
    .peezyCardChrome()
}
#endif
