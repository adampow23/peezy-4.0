//
//  FlowEngineView.swift
//  Peezy 4.0
//
//  Renders a FlowDefinition through the Task Card Components kit (Spec 04
//  Phase A). Replaces the 38 templated flow screens: same chrome
//  (InteractiveBackground + TaskFlowStack + inert dismiss shim), same kit
//  components, same submitWorkflowAnswers payload — the step ids ARE the
//  answer keys the old screens used.
//
//  What is new versus the old screens:
//  - Answers persist per step on the task doc (flowAnswers.{stepId}) and the
//    visited trail persists as flowPath — a killed app resumes at the same
//    step with selections intact. State clears on flow terminals so a
//    concluded flow reopens fresh (the old screens' semantics).
//  - Steps may declare a spine `stage`; entering one writes it via
//    TaskActionService.setStage.
//
//  Kit component defaults restated here (question/timeSaved/labels) are
//  copied verbatim from the component declarations — the definitions only
//  store values the old screens passed explicitly.
//

import SwiftUI
import FirebaseFirestore

// MARK: - Flow Inputs

/// User context a definition can reference (address confirm steps, date
/// confirm steps). Built by the router from UserState with the same
/// fallbacks the old TaskFlowRouter cases used.
struct FlowInputs {
    let currentAddress: String
    let newAddress: String
    let moveDate: Date
}

// MARK: - Flow Engine View

struct FlowEngineView: View {
    let definition: FlowDefinition
    let userId: String
    let taskId: String
    let inputs: FlowInputs
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    // MARK: - State

    /// Visited step ids; last element is the current step. Persisted as flowPath.
    @State private var path: [String] = []
    /// Answers keyed by step id. Persisted as flowAnswers. Back-navigation
    /// keeps recorded answers (the old screens never removed keys).
    @State private var answers: [String: [String]] = [:]
    @State private var isSubmitting = false
    @State private var isRestoring = true

    private let actionService = TaskActionService()

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            InteractiveBackground()
                .ignoresSafeArea()

            if !isRestoring, let step = currentStep {
                TaskFlowStack(cardsRemaining: cardsRemaining, currentIndex: path.count - 1) {
                    cardContent(for: step)
                        .accessibilityIdentifier("flow.\(definition.workflowId).\(step.id)")
                }
            } else {
                ProgressView()
                    .tint(PeezyTheme.Colors.deepInk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("flow.\(definition.workflowId).loading")
            }

            TaskFlowDismissButton(onDismiss: onDismiss)
        }
        .task {
            await restoreState()
        }
    }

    // MARK: - Current Step

    private var currentStep: FlowStep? {
        guard let id = path.last else { return nil }
        return definition.step(withId: id)
    }

    private var canGoBack: Bool { path.count > 1 }

    /// Steps left along the current route (current step included) — drives
    /// the decorative depth cards exactly like the old screens' skip-aware
    /// count: answered branches are honored, unanswered steps follow `next`.
    private var cardsRemaining: Int {
        var count = 0
        var cursor = path.last
        var guardRail = 0
        while let id = cursor, let step = definition.step(withId: id), guardRail < definition.steps.count {
            count += 1
            guardRail += 1
            if let answer = answers[step.id]?.first, let branch = matchingBranch(for: step, value: answer) {
                cursor = branch.next
            } else {
                cursor = step.next
            }
        }
        return max(count, 1)
    }

    // MARK: - Card Rendering

    @ViewBuilder
    private func cardContent(for step: FlowStep) -> some View {
        switch step.kind {

        case .title:
            TaskFlowTitleCard(
                taskTitle: definition.taskTitle,
                icon: step.icon ?? "circle",
                onContinue: { advance(from: step, selected: nil) }
            )

        case .info:
            TaskFlowInfoCard(
                taskTitle: definition.taskTitle,
                title: step.infoTitle ?? "Good to Know",
                bodyText: step.body ?? "",
                primaryLabel: step.primaryLabel ?? "Got it",
                showBack: canGoBack,
                onPrimary: { advance(from: step, selected: nil) },
                onBack: { goBack() }
            )

        case .decision:
            TaskFlowDecisionCard(
                taskTitle: definition.taskTitle,
                question: step.question ?? "Would you like us to take care of this for you?",
                timeSaved: step.timeSaved ?? "~1 hr",
                showBack: canGoBack,
                onPeezy: {
                    record(step.id, ["peezy"])
                    advance(from: step, selected: "peezy")
                },
                onSelf: {
                    record(step.id, ["self"])
                    advance(from: step, selected: "self")
                },
                onBack: { goBack() }
            )

        case .select:
            TaskFlowTilesCard(
                taskTitle: definition.taskTitle,
                question: step.question ?? "",
                options: (step.options ?? []).map { FlowOption(id: $0.id, label: $0.label, icon: $0.icon) },
                mode: .single,
                selectedIds: Set(answers[step.id] ?? []),
                showBack: canGoBack,
                onSelect: { optionId in
                    record(step.id, [optionId])
                    advance(from: step, selected: optionId)
                },
                onBack: { goBack() }
            )

        case .businessSearch:
            TaskFlowBusinessSearchCard(
                taskTitle: definition.taskTitle,
                question: step.question ?? "",
                placeholder: step.placeholder ?? "Search...",
                searchHint: step.searchHint ?? "",
                selectedBusiness: answers[step.id]?.first,
                showBack: canGoBack,
                onConfirm: { name in
                    record(step.id, [name])
                    advance(from: step, selected: name)
                },
                onBack: { goBack() }
            )

        case .confirmAddress:
            TaskFlowConfirmAddressCard(
                taskTitle: definition.taskTitle,
                question: step.question ?? "",
                currentAddress: step.addressSource == "new" ? inputs.newAddress : inputs.currentAddress,
                displayIcon: step.displayIcon ?? "mappin.and.ellipse",
                showBack: canGoBack,
                onConfirm: { address in
                    record(step.id, [address])
                    advance(from: step, selected: address)
                },
                onBack: { goBack() }
            )

        case .confirmDate:
            TaskFlowConfirmDateCard(
                taskTitle: definition.taskTitle,
                question: step.question ?? "Is this your move date?",
                currentDate: inputs.moveDate,
                showBack: canGoBack,
                onConfirm: { date in
                    let formatter = ISO8601DateFormatter()
                    record(step.id, [formatter.string(from: date)])
                    advance(from: step, selected: nil)
                },
                onBack: { goBack() }
            )

        case .summary:
            TaskFlowSummaryCard(
                taskTitle: definition.taskTitle,
                bodyText: summaryBody(for: step),
                subtext: step.subtext,
                showBack: canGoBack,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )

        case .status:
            TaskFlowStatusCard(
                taskTitle: definition.taskTitle,
                showBack: canGoBack,
                onLater: { concludeFlow { onStatusAction(.later) } },
                onInProgress: { concludeFlow { onStatusAction(.inProgress) } },
                onDone: { concludeFlow { onStatusAction(.done) } },
                onBack: { goBack() }
            )
        }
    }

    /// First bodyVariant whose `when` pairs all match recorded answers,
    /// else the step's default body — the ManageBank-family dynamic
    /// find-summary text, generalized.
    private func summaryBody(for step: FlowStep) -> String {
        if let variants = step.bodyVariants {
            for variant in variants where conditionsSatisfied(variant.when) {
                return variant.body
            }
        }
        return step.body ?? ""
    }

    private func conditionsSatisfied(_ when: [String: String]) -> Bool {
        when.allSatisfy { key, value in answers[key]?.first == value }
    }

    // MARK: - Navigation

    private func matchingBranch(for step: FlowStep, value: String) -> FlowBranch? {
        step.branches?.first { branch in
            branch.value == value && conditionsSatisfied(branch.when ?? [:])
        }
    }

    private func advance(from step: FlowStep, selected: String?) {
        let nextId: String?
        if let selected, let branch = matchingBranch(for: step, value: selected) {
            nextId = branch.next
        } else {
            nextId = step.next
        }
        guard let nextId, let nextStep = definition.step(withId: nextId) else { return }

        path.append(nextId)
        persistProgress(answerKey: nil, values: nil)

        if let stageRaw = nextStep.stage, let stage = TaskStage(rawValue: stageRaw) {
            let id = taskId
            Task { await actionService.setStage(taskId: id, stage: stage) }
        }
    }

    private func goBack() {
        guard canGoBack else { return }
        path.removeLast()
        persistProgress(answerKey: nil, values: nil)
    }

    // MARK: - Answers + Persistence

    private func record(_ key: String, _ values: [String]) {
        answers[key] = values
        persistProgress(answerKey: key, values: values)
    }

    private func persistProgress(answerKey: String?, values: [String]?) {
        guard !taskId.isEmpty else { return }
        let id = taskId
        let snapshot = path
        Task {
            await actionService.writeFlowProgress(taskId: id, path: snapshot, answerKey: answerKey, values: values)
        }
    }

    /// Clears persisted flow state, then fires the terminal callback —
    /// status-card exits (later / in progress / done).
    private func concludeFlow(_ callback: @escaping () -> Void) {
        let id = taskId
        Task { await actionService.clearFlowState(taskId: id) }
        callback()
    }

    // MARK: - Resume

    private func restoreState() async {
        defer { isRestoring = false }

        let entry = definition.steps.first?.id ?? ""

        guard !taskId.isEmpty, !userId.isEmpty else {
            path = [entry]
            return
        }

        let db = Firestore.firestore()
        let doc = try? await db.collection("users").document(userId)
            .collection("tasks").document(taskId).getDocument()
        let data = doc?.data()

        let savedPath = data?["flowPath"] as? [String] ?? []
        let savedAnswers = (data?["flowAnswers"] as? [String: Any])?
            .compactMapValues { $0 as? [String] } ?? [:]

        // A reseed can rename steps; a trail referencing unknown ids restarts.
        let pathIsValid = !savedPath.isEmpty && savedPath.allSatisfy { definition.step(withId: $0) != nil }

        if pathIsValid {
            path = savedPath
            answers = savedAnswers
        } else {
            path = [entry]
        }
    }

    // MARK: - Submission (summary terminal)

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true

        var workflowAnswers = WorkflowAnswers(workflowId: definition.workflowId)
        workflowAnswers.answers = answers

        let id = taskId
        Task {
            do {
                let service = WorkflowService()
                let response = try await service.submitAnswers(
                    workflowId: definition.workflowId,
                    answers: workflowAnswers,
                    userId: userId
                )
                await actionService.clearFlowState(taskId: id)
                await MainActor.run {
                    isSubmitting = false
                    if response.success { onComplete() }
                }
            } catch {
                // Old screens completed on error too — submission is
                // best-effort past this point.
                await actionService.clearFlowState(taskId: id)
                await MainActor.run {
                    isSubmitting = false
                    onComplete()
                }
            }
        }
    }
}
