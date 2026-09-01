//
//  FindCleanersFlow.swift
//  Peezy 4.0
//
//  Created by Adam Powell on 4/13/26.
//

import SwiftUI

// MARK: - Find Cleaners Flow
// Type 6: Complex-Vendor
//
// Card sequence:
//   TitleCard → Multi4 (services) → Select4 (move-out timing) → SummaryCard

struct FindCleanersFlow: View {
    let taskTitle = "Find my cleaners"
    let workflowId = "book_cleaners"

    let userId: String
    let taskId: String
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    @Environment(FlowExitCoordinator.self) private var exitCoordinator

    // MARK: - State

    @State private var currentIndex = 0
    @State private var answers: [String: Set<String>] = [:]
    @State private var isSubmitting = false
    @State private var submissionError: String?
    @State private var submissionAttempt = 0
    @State private var terminalSubmissionState = FlowTerminalSubmissionState()

    // MARK: - Card Indices

    private let titleCard = 0
    private let servicesCard = 1
    private let moveOutTimingCard = 2
    private let summaryCard = 3
    private let totalCards = 4

    private var cardsRemaining: Int {
        totalCards - currentIndex
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: cardsRemaining, currentIndex: currentIndex) {
                cardContent
            }
        }
        .resumableFlowProgress(
            path: ["card.\(currentIndex)"],
            answers: FlowProgressCoding.encode(answers)
        ) { restored in
            currentIndex = min(max(FlowProgressCoding.cardIndex(from: restored.path), 0), totalCards - 1)
            var restoredAnswers = FlowProgressCoding.decode(restored.answers)
            if restoredAnswers["which_place"]?.contains("both") == true {
                restoredAnswers["which_place"] = ["both"]
                restoredAnswers["move_in_timing"] = ["flexible"]
            } else {
                restoredAnswers["which_place"] = ["move_out"]
                restoredAnswers.removeValue(forKey: "move_in_timing")
            }
            answers = restoredAnswers
        }
    }

    // MARK: - Card Router

    @ViewBuilder
    private var cardContent: some View {
        switch currentIndex {

        // ── Card 0: Title ──
        case titleCard:
            TaskFlowTitleCard(
                taskTitle: taskTitle,
                icon: "sparkles",
                onContinue: { advance() }
            )

        // ── Card 1: Services needed (multi-select) ──
        case servicesCard:
            TaskFlowMulti4Card(
                taskTitle: taskTitle,
                question: "What services do you need?",
                option1: FlowOption(id: "standard", label: "Standard clean", icon: "sparkles"),
                option2: FlowOption(id: "deep", label: "Deep clean", icon: "bubbles.and.sparkles"),
                option3: FlowOption(id: "carpet", label: "Carpet cleaning", icon: "square.grid.3x3.topleft.filled"),
                option4: FlowOption(id: "windows", label: "Window cleaning", icon: "window.horizontal"),
                selectedIds: answers["services"] ?? [],
                showBack: true,
                onSelect: { id in toggleMulti("services", id: id) },
                onContinue: { advance() },
                onBack: { goBack() }
            )

        // ── Card 2: Move-out clean timing ──
        case moveOutTimingCard:
            TaskFlowSelect4Card(
                taskTitle: taskTitle,
                question: "When do you need the move-out clean?",
                option1: FlowOption(id: "morning", label: "Morning", icon: "sunrise"),
                option2: FlowOption(id: "afternoon", label: "Afternoon", icon: "sun.max"),
                option3: FlowOption(id: "evening", label: "Evening", icon: "sunset"),
                option4: FlowOption(id: "flexible", label: "Flexible", icon: "clock"),
                selectedIds: answers["move_out_timing"] ?? [],
                showBack: true,
                onSelect: { id in selectSingle("move_out_timing", id: id) },
                onBack: { goBack() }
            )

        // ── Card 3: Summary ──
        case summaryCard:
            TaskFlowSummaryCard(
                taskTitle: taskTitle,
                bodyText: actionSheetText,
                primaryLabel: submissionError == nil ? "Done" : "Try again",
                subtext: submissionError ?? "Use the same details with each cleaner so the quotes are easy to compare.",
                showBack: true,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )
            .id("summary.\(submissionAttempt)")
            .overlay(alignment: .bottom) {
                Toggle(
                    "Want the new place cleaned too?",
                    isOn: cleanersAddNewPlaceBinding
                )
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PeezyTheme.Colors.deepInk)
                .tint(PeezyTheme.Colors.deepInk)
                .frame(minHeight: 44)
                .padding(.horizontal, 24)
                .padding(.bottom, 92)
                .disabled(isSubmitting || exitCoordinator.isTerminalizing)
                .accessibilityIdentifier("cleanersAddNewPlaceToggle")
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Navigation

    private func advance() {
        guard !isSubmitting, !exitCoordinator.isTerminalizing else { return }
        guard currentIndex + 1 < totalCards else { return }
        currentIndex += 1
    }

    private func goBack() {
        guard !isSubmitting, !exitCoordinator.isTerminalizing else { return }
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    // MARK: - Answer Handlers

    private func selectSingle(_ key: String, id: String) {
        if FlowAnswerMutationGate.apply(
            isSubmitting: isSubmitting,
            isTerminalizing: exitCoordinator.isTerminalizing,
            mutation: { answers[key] = [id] }
        ) {
            advance()
        }
    }

    private func toggleMulti(_ key: String, id: String) {
        FlowAnswerMutationGate.apply(
            isSubmitting: isSubmitting,
            isTerminalizing: exitCoordinator.isTerminalizing
        ) {
            if answers[key] == nil { answers[key] = [] }
            if answers[key]!.contains(id) {
                answers[key]!.remove(id)
            } else {
                answers[key]!.insert(id)
            }
        }
    }

    private var cleanersAddNewPlaceBinding: Binding<Bool> {
        Binding(
            get: { answers["which_place"]?.contains("both") == true },
            set: { includesNewPlace in
                FlowAnswerMutationGate.apply(
                    isSubmitting: isSubmitting,
                    isTerminalizing: exitCoordinator.isTerminalizing
                ) {
                    if includesNewPlace {
                        answers["which_place"] = ["both"]
                        answers["move_in_timing"] = ["flexible"]
                    } else {
                        answers["which_place"] = ["move_out"]
                        answers.removeValue(forKey: "move_in_timing")
                    }
                }
            }
        )
    }

    private var actionSheetText: String {
        let place = labels(
            for: "which_place",
            mapping: ["move_out": "old place", "move_in": "new place", "both": "both places"]
        )
        let services = labels(
            for: "services",
            mapping: ["standard": "standard clean", "deep": "deep clean", "carpet": "carpet cleaning", "windows": "window cleaning"]
        )
        let moveOutTiming = labels(
            for: "move_out_timing",
            mapping: ["morning": "morning", "afternoon": "afternoon", "evening": "evening", "flexible": "flexible"]
        )
        let moveInTiming = labels(
            for: "move_in_timing",
            mapping: ["morning": "morning", "afternoon": "afternoon", "evening": "evening", "flexible": "flexible"]
        )

        var ready = ["• Place: \(place)", "• Services: \(services)"]
        if !moveOutTiming.isEmpty { ready.append("• Move-out timing: \(moveOutTiming)") }
        if !moveInTiming.isEmpty { ready.append("• Move-in timing: \(moveInTiming)") }

        return "You're set. Here's everything you need.\n\nWhat to say\n“I need \(services) for my \(place). What is included, when are you available, and what is your cancellation policy?”\n\nWhat to have ready\n\(ready.joined(separator: "\n"))"
    }

    private func labels(for key: String, mapping: [String: String]) -> String {
        (answers[key] ?? [])
            .map { mapping[$0] ?? $0.replacingOccurrences(of: "_", with: " ") }
            .sorted()
            .joined(separator: ", ")
    }

    // MARK: - Submission

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil
        let preSubmitBarrier = exitCoordinator.beginPreSubmitBarrier()

        var submissionAnswers = answers
        if submissionAnswers["which_place"]?.contains("both") == true {
            submissionAnswers["which_place"] = ["both"]
            submissionAnswers["move_in_timing"] = ["flexible"]
        } else {
            submissionAnswers["which_place"] = ["move_out"]
            submissionAnswers.removeValue(forKey: "move_in_timing")
        }
        let workflowAnswers = FlowProgressCoding.workflowAnswers(
            workflowId: workflowId,
            setAnswers: submissionAnswers
        )

        Task { @MainActor in
            do {
                let persistedFlowAttemptId = try await preSubmitBarrier.value
                try await terminalSubmissionState.run(
                    submit: {
                        let response = try await WorkflowService().submitAnswers(
                            workflowId: workflowId,
                            answers: workflowAnswers,
                            userId: userId,
                            submissionToken: WorkflowSubmissionToken.make(
                                userId: userId,
                                taskId: taskId,
                                workflowId: workflowId,
                                flowAttemptId: persistedFlowAttemptId
                            )
                        )
                        guard response.success else { throw FlowTerminalSubmissionError.rejected }
                    },
                    clear: {
                        exitCoordinator.beginTerminalization()
                        try await exitCoordinator.terminalize {
                            try await TaskActionService().clearFlowState(taskId: taskId)
                        }
                    },
                    onSuccess: {
                        isSubmitting = false
                        onComplete()
                    }
                )
            } catch {
                isSubmitting = false
                exitCoordinator.releaseSubmissionLockAfterFailure()
                if terminalSubmissionState.submissionSucceeded {
                    submissionError = "Your answers were saved, but the completed flow couldn't be cleared. Check your connection, then try again."
                } else {
                    submissionError = "Couldn't save your answers. Check your connection, then try again."
                }
                submissionAttempt += 1
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Find Cleaners Flow") {
    FindCleanersFlow(
        userId: "preview-user",
        taskId: "BOOK_CLEANERS",
        onComplete: { print("✅ Complete") },
        onDismiss: { print("⏪ Dismiss") },
        onStatusAction: { action in print("📋 Status: \(action)") }
    )
}
#endif
