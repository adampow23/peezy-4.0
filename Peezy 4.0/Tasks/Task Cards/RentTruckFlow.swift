import SwiftUI

struct RentTruckFlow: View {
    let taskTitle = "Rent my moving truck"
    let workflowId = "rent_truck"

    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var submissionAttempt = 0

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
        }
        .resumableFlowProgress(
            path: ["card.\(currentIndex)"],
            answers: FlowProgressCoding.encode(answers)
        ) { restored in
            currentIndex = min(max(FlowProgressCoding.cardIndex(from: restored.path), 0), totalCards - 1)
            answers = FlowProgressCoding.decode(restored.answers)
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
                bodyText: actionSheetText,
                primaryLabel: submissionError == nil ? "Done" : "Try again",
                subtext: submissionError ?? "Compare the full checkout total, mileage rules, and pickup location before booking.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )
            .id("summary.\(submissionAttempt)")

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
        advance()
    }

    private var actionSheetText: String {
        let tripType: String
        switch answers["trip_type"]?.first {
        case "one_way": tripType = "one-way rental"
        case "round_trip": tripType = "return to the same location"
        default: tripType = "your selected rental type"
        }
        return "You're set. Here's everything you need.\n\nWhat to say\n“I need a \(tripType). What truck sizes are available for my date, and what is included in the full checkout total?”\n\nWhat to have ready\nPickup and drop-off locations, move date, inventory size, driver details, and expected mileage."
    }

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil
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
                    if response.success {
                        onComplete()
                    } else {
                        submissionError = "Couldn't save your answers. Check your connection, then try again."
                        submissionAttempt += 1
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "Couldn't save your answers. Check your connection, then try again."
                    submissionAttempt += 1
                }
            }
        }
    }
}

#if DEBUG
#Preview("Rent Truck Flow") {
    RentTruckFlow(
        userId: "preview-user",
        taskId: "RENT_TRUCK",
        onComplete: { print("Complete") },
        onDismiss: { print("Dismiss") },
        onStatusAction: { action in print("Status: \(action)") }
    )
}
#endif
