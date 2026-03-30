import SwiftUI

struct TaskFlowView: View {
    let task: PeezyCard
    let userState: UserState?
    let onDismiss: () -> Void
    let onStartWorkflow: (() -> Void)?

    @State private var flowState: FlowState = .entry

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
                        onUpdate: { flowState = .confirmDetails },
                        onCancel: { flowState = .confirmDetails }
                    )

                case .confirmDetails:
                    ConfirmDetailsView(
                        task: task,
                        userState: userState,
                        onConfirm: { _ in flowState = .submitted },
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

            // Dismiss button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.5))
                            .frame(width: 36, height: 36)
                            .background {
                                Circle()
                                    .foregroundStyle(.regularMaterial)
                                    .overlay {
                                        Circle()
                                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                    }
                            }
                    }
                    .padding(.trailing, 24)
                    .padding(.top, 16)
                }
                Spacer()
            }
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
            flowState = .confirmDetails
        }
    }

    private func handleBack() {
        switch task.taskType {
        case "transfer_cancel":
            flowState = .transferChoice
        default:
            flowState = .choiceScreen
        }
    }
}

// MARK: - Previews

#Preview("Research Task") {
    TaskFlowView(
        task: PeezyCard(
            type: .task,
            title: "Research Internet Providers",
            subtitle: "Find the best internet plan at your new address.",
            taskType: "research"
        ),
        userState: {
            var state = UserState(userId: "preview", name: "Alex")
            state.originCity = "Austin"
            state.originState = "TX"
            state.destinationCity = "Denver"
            state.destinationState = "CO"
            state.moveDate = Calendar.current.date(byAdding: .day, value: 30, to: Date())
            return state
        }(),
        onDismiss: {},
        onStartWorkflow: nil
    )
}

#Preview("Survey Task") {
    TaskFlowView(
        task: PeezyCard(
            type: .task,
            title: "Moving Preferences Survey",
            subtitle: "Help us personalize your moving plan.",
            taskType: "survey"
        ),
        userState: nil,
        onDismiss: {},
        onStartWorkflow: {}
    )
}

#Preview("Transfer Cancel Task") {
    TaskFlowView(
        task: PeezyCard(
            type: .task,
            title: "Transfer Gym Membership",
            subtitle: "Decide whether to transfer or cancel your current membership.",
            taskType: "transfer_cancel"
        ),
        userState: nil,
        onDismiss: {},
        onStartWorkflow: nil
    )
}

#Preview("Provide Info Task") {
    TaskFlowView(
        task: PeezyCard(
            type: .task,
            title: "Set Up Utilities",
            subtitle: "Contact your utility providers before move day.",
            taskType: "provide_info"
        ),
        userState: nil,
        onDismiss: {},
        onStartWorkflow: nil
    )
}
