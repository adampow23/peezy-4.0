import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct TaskFlowView: View {
    let task: PeezyCard
    let userState: UserState?
    let onDismiss: () -> Void
    let onStartWorkflow: (() -> Void)?

    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var flowState: FlowState = .entry
    @State private var confirmedData: [String: String] = [:]
    @State private var transferChoiceLabel: String? = nil
    @State private var submitError: String? = nil

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    enum FlowState {
        case entry          // Universal entry (all types)
        case choiceScreen   // Research + Survey: "Peezy handle" / "self handle"
        case transferChoice // Transfer/Cancel: "update" / "cancel"
        case confirmDetails // Pre-filled confirmation
        case submitted      // "We're on it"
        case staticInfo     // Tips/guidance for self-handle OR provide_info
        case paywall        // Subscription gate for gated task types
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

                case .paywall:
                    PaywallGateView(onDismiss: {
                        if subscriptionManager.isSubscribed {
                            handleStart()
                        } else {
                            onDismiss()
                        }
                    })
                }
            }
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            // Submission error toast — shown if Firestore write fails
            if let error = submitError {
                VStack {
                    Spacer()
                    ErrorToast(message: error) {
                        submitError = nil
                    }
                    .padding(.bottom, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.3), value: flowState)
        .animation(.spring(response: 0.4), value: submitError != nil)
    }

    private func handleStart() {
        guard subscriptionManager.isSubscribed else {
            flowState = .paywall
            return
        }
        switch task.taskType {
        case "provide_info":
            flowState = .staticInfo
        case "research", "survey":
            flowState = .choiceScreen
        case "transfer_cancel":
            flowState = .transferChoice
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
        // Fire webhook — failure is intentionally silent (best-effort notification)
        WebhookService.sendTaskSubmission(
            userId: userState?.userId ?? "unknown",
            userName: userState?.name ?? "Unknown",
            taskId: task.taskId ?? "unknown",
            taskTitle: task.title,
            taskType: task.taskType ?? "unknown",
            confirmedFields: data,
            transferChoice: transferChoiceLabel
        )

        // If no auth/taskId, advance optimistically — nothing to write
        guard let userId = Auth.auth().currentUser?.uid,
              let taskId = task.taskId else {
            flowState = .submitted
            return
        }

        let db = Firestore.firestore()
        let taskRef = db.collection("users").document(userId)
            .collection("tasks").document(taskId)

        Task {
            do {
                try await taskRef.updateData([
                    "status": "PendingPeezy",
                    "confirmedFields": data,
                    "submittedAt": FieldValue.serverTimestamp()
                ])
                await MainActor.run { flowState = .submitted }
            } catch {
                await MainActor.run {
                    submitError = "Submission failed. Please check your connection and try again."
                }
            }
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
