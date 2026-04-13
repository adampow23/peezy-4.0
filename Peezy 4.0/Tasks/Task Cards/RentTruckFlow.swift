import SwiftUI

struct RentTruckFlow: View {
    let taskTitle = "Rent my moving truck"
    let workflowId = "rent_truck"

    let userId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false

    private let titleCard = 0
    private let tripTypeCard = 1
    private let summaryCard = 2
    private let totalCards = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()
            TaskFlowStack(cardsRemaining: totalCards - currentIndex, currentIndex: currentIndex) {
                cardContent
            }
            TaskFlowDismissButton(onDismiss: onDismiss)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch currentIndex {
        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "truck.box.fill",
                onContinue: { advance() }
            )

        case tripTypeCard:
            TaskFlowSelect2Card(
                taskTitle: taskTitle,
                question: "What type of rental?",
                option1: FlowOption(id: "one_way", label: "One-way rental", icon: "arrow.right"),
                option2: FlowOption(id: "round_trip", label: "Return to same location", icon: "arrow.triangle.2.circlepath"),
                selectedIds: answers["trip_type"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("trip_type", id: id) },
                onBack: { goBack() }
            )

        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: "We'll compare options from the major rental companies and get you the best deal.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        default:
            EmptyView()
        }
    }

    private func advance() {
        guard currentIndex + 1 < totalCards else { return }
        currentIndex += 1
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func selectSingle(_ key: String, id: String) {
        answers[key] = [id]
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            advance()
        }
    }

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true
        var workflowAnswers = WorkflowAnswers(workflowId: workflowId)
        workflowAnswers.answers = answers.mapValues { Array($0) }
        Task {
            do {
                let service = WorkflowService()
                let response = try await service.submitAnswers(
                    workflowId: workflowId, answers: workflowAnswers, userId: userId
                )
                await MainActor.run {
                    isSubmitting = false
                    if response.success { onComplete() }
                }
            } catch {
                await MainActor.run { isSubmitting = false; onComplete() }
            }
        }
    }
}

#if DEBUG
#Preview("Rent Truck Flow") {
    RentTruckFlow(
        userId: "preview-user",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
