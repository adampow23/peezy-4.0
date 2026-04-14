//
//  TaskFlowStatusCard.swift
//  Peezy 4.0
//
//  Final card for self-service flows. Asks the user what they're doing about the task.
//  Three hardcoded options — each triggers a different action.
//  "Already done" fires confetti — celebration at the moment of accomplishment.
//  "Later" and "Mark as in progress" dismiss immediately, no confetti.
//

import SwiftUI

struct TaskFlowStatusCard: View {
    let taskTitle: String
    var question: String = "What's the plan with this?"
    var showBack: Bool = false
    let onLater: () -> Void
    let onInProgress: () -> Void
    let onDone: () -> Void
    var onBack: (() -> Void)? = nil

    @State private var confettiActive = false
    @State private var tapped = false

    var body: some View {
        ZStack {
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
                    guard !tapped else { return }
                    switch id {
                    case "later":
                        onLater()
                    case "in_progress":
                        onInProgress()
                    case "done":
                        tapped = true
                        confettiActive = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onDone()
                        }
                    default:
                        break
                    }
                },
                onBack: onBack
            )

            ConfettiView(isActive: $confettiActive, intensity: .high)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

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
