import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct TaskFlowView: View {
    let task: PeezyCard
    let userState: UserState?
    let onDismiss: () -> Void
    let onStartWorkflow: (() -> Void)?

    @State private var flowState: FlowState = .entry
    @State private var confirmedData: [String: String] = [:]
    @State private var transferChoiceLabel: String? = nil

    enum FlowState {
        case entry          // Universal entry (all types)
        case choiceScreen   // Research + Survey: "Peezy handle" / "self handle"
        case transferChoice // Transfer/Cancel: "update" / "cancel"
        case confirmDetails // Pre-filled confirmation
        case submitted      // "We're on it"
        case staticInfo     // Tips/guidance for self-handle OR provide_info
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            Group {
                switch flowState {
                case .entry:
                    TaskEntryView(
                        task: task,
                        onStart: { handleStart() },
                        onSkip: { onDismiss() }
                    )

                case .choiceScreen:
                    TaskChoiceView(
                        task: task,
                        onPeezyHandle: { handlePeezyHandle() },
                        onSelfHandle: { flowState = .staticInfo }
                    )

                case .transferChoice:
                    TransferDecisionView(
                        task: task,
                        isInterstate: userState?.isLongDistance ?? false,
                        onUpdate: { transferChoiceLabel = "update"; transitionToConfirmOrSubmit() },
                        onCancel: { transferChoiceLabel = "cancel"; transitionToConfirmOrSubmit() }
                    )

                case .confirmDetails:
                    ConfirmDetailsView(
                        task: task,
                        userState: userState,
                        onConfirm: { data in
                            confirmedData = data
                            submitTask(with: data)
                        },
                        onBack: { handleBack() }
                    )

                case .submitted:
                    SubmittedView(
                        task: task,
                        onDone: { onDismiss() }
                    )

                case .staticInfo:
                    StaticInfoView(
                        task: task,
                        onComplete: { onDismiss() },
                        onLater: { onDismiss() }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

        }
        .animation(.easeInOut(duration: 0.3), value: flowState)
    }

    private func handleStart() {
        switch task.taskType {
        case "research", "survey":
            flowState = .choiceScreen
        case "transfer_cancel":
            flowState = .transferChoice
        case "provide_info":
            flowState = .staticInfo
        default:
            flowState = .staticInfo
        }
    }

    private func handlePeezyHandle() {
        if task.taskType == "survey" {
            onDismiss()
            onStartWorkflow?()
        } else {
            transitionToConfirmOrSubmit()
        }
    }

    private func transitionToConfirmOrSubmit() {
        flowState = task.taskId == "RENT_TRUCK" ? .submitted : .confirmDetails
    }

    private func handleBack() {
        switch task.taskType {
        case "transfer_cancel":
            flowState = .transferChoice
        default:
            flowState = .choiceScreen
        }
    }

    private func submitTask(with data: [String: String]) {
        flowState = .submitted

        // Fire webhook — failure is silent
        WebhookService.sendTaskSubmission(
            userId: userState?.userId ?? "unknown",
            userName: userState?.name ?? "Unknown",
            taskId: task.taskId ?? "unknown",
            taskTitle: task.title,
            taskType: task.taskType ?? "unknown",
            confirmedFields: data,
            transferChoice: transferChoiceLabel
        )

        // Update Firestore task status
        guard let userId = Auth.auth().currentUser?.uid,
              let taskId = task.taskId else { return }

        let db = Firestore.firestore()
        let taskRef = db.collection("users").document(userId)
            .collection("tasks").document(taskId)

        Task {
            try? await taskRef.updateData([
                "status": "PendingPeezy",
                "confirmedFields": data,
                "submittedAt": FieldValue.serverTimestamp()
            ])
        }
    }
}

// MARK: - Previews

#Preview("Research Flow") {
    TaskFlowView(
        task: .previewResearch,
        userState: .preview,
        onDismiss: {},
        onStartWorkflow: nil
    )
}

#Preview("Survey Flow") {
    TaskFlowView(
        task: .previewSurvey,
        userState: .preview,
        onDismiss: {},
        onStartWorkflow: { print("Workflow launched") }
    )
}

#Preview("Transfer Flow") {
    TaskFlowView(
        task: .previewTransfer,
        userState: .preview,
        onDismiss: {},
        onStartWorkflow: nil
    )
}

#Preview("Provide Info Flow") {
    TaskFlowView(
        task: .previewProvideInfo,
        userState: .preview,
        onDismiss: {},
        onStartWorkflow: nil
    )
}
