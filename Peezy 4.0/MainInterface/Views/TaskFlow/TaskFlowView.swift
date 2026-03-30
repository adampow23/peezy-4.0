import SwiftUI

struct TaskFlowView: View {
    let task: PeezyCard
    let userState: UserState?
    let onDismiss: () -> Void

    @State private var flowState: FlowState = .entry

    enum FlowState {
        case entry
        case researchIntro
        case confirmDetails
        case submitted
        case transferDecision
        case survey
        case staticInfo
        case selfHandle
    }

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            Group {
                switch flowState {
                case .entry, .survey:
                    ResearchIntroView(
                        task: task,
                        onPeezyHandle: { flowState = .confirmDetails },
                        onSelfHandle: { flowState = .selfHandle }
                    )

                case .researchIntro:
                    ResearchIntroView(
                        task: task,
                        onPeezyHandle: { flowState = .confirmDetails },
                        onSelfHandle: { flowState = .selfHandle }
                    )

                case .confirmDetails:
                    ConfirmDetailsView(
                        task: task,
                        userState: userState,
                        onConfirm: { confirmedData in
                            print("[TaskFlow] Confirmed details: \(confirmedData)")
                            flowState = .submitted
                        },
                        onBack: { flowState = .researchIntro }
                    )

                case .submitted:
                    SubmittedView(
                        task: task,
                        onDone: { onDismiss() }
                    )

                case .transferDecision:
                    TransferDecisionView(
                        task: task,
                        isInterstate: userState?.isLongDistance ?? false,
                        onUpdate: { flowState = .confirmDetails },
                        onCancel: { flowState = .confirmDetails },
                        onNotSure: { flowState = .confirmDetails }
                    )

                case .staticInfo:
                    StaticInfoView(
                        task: task,
                        onComplete: { onDismiss() },
                        onLater: { flowState = .selfHandle }
                    )

                case .selfHandle:
                    SelfHandleView(
                        task: task,
                        onSelectDate: { _ in onDismiss() },
                        onAlreadyDone: { onDismiss() }
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
        .onAppear {
            flowState = initialFlowState(for: task)
        }
    }

    private func initialFlowState(for task: PeezyCard) -> FlowState {
        switch task.taskType {
        case "provide_info":
            return .staticInfo
        case "survey":
            return .entry
        case "transfer_cancel":
            return .transferDecision
        case "research":
            return .researchIntro
        default:
            return .staticInfo
        }
    }
}

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
        onDismiss: {}
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
        onDismiss: {}
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
        onDismiss: {}
    )
}
