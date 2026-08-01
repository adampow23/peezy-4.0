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
    let isLongDistance: Bool
}

private struct ActiveProviderAction {
    let stepId: String
    let resolution: ProviderResolution
    let kind: ProviderActionKind
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

    @Environment(FlowExitCoordinator.self) private var exitCoordinator

    // MARK: - State

    /// Visited step ids; last element is the current step. Persisted as flowPath.
    @State private var path: [String] = []
    /// Answers keyed by step id. Persisted as flowAnswers. Back-navigation
    /// keeps recorded answers (the old screens never removed keys).
    @State private var answers: [String: [String]] = [:]
    /// Rows stamped on the task doc by generation (flowRows) and the
    /// definition's steps specialized to them (Spec 04 Phase B).
    @State private var rows: [FlowRow] = []
    @State private var resolvedSteps: [FlowStep] = []
    @State private var isSubmitting = false
    @State private var isRestoring = true
    @State private var resolvingProviderStepId: String?
    @State private var activeProviderAction: ActiveProviderAction?
    @State private var providerResolveTask: Task<Void, Never>?
    /// Hard paywall gate (option (c), Spec 04 Phase D): raised when an
    /// unsubscribed user reaches a gated submission.
    @State private var showPaywallGate = false

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
        }
        .task {
            await restoreState()
        }
        .onDisappear {
            providerResolveTask?.cancel()
        }
        .fullScreenCover(isPresented: $showPaywallGate) {
            PaywallGateSheet(action: .conciergeSubmission) { subscribed in
                showPaywallGate = false
                if subscribed { submitAndComplete() }
            }
        }
    }

    // MARK: - Current Step

    private func resolvedStep(withId id: String) -> FlowStep? {
        resolvedSteps.first { $0.id == id }
    }

    private var currentStep: FlowStep? {
        guard let id = path.last else { return nil }
        return resolvedStep(withId: id)
    }

    private var canGoBack: Bool { path.count > 1 }

    /// Steps left along the current route (current step included) — drives
    /// the decorative depth cards exactly like the old screens' skip-aware
    /// count: answered branches are honored, unanswered steps follow `next`.
    private var cardsRemaining: Int {
        var count = 0
        var cursor = path.last
        var guardRail = 0
        while let id = cursor, let step = resolvedStep(withId: id), guardRail < resolvedSteps.count {
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
            if resolvingProviderStepId == step.id {
                ProviderResolutionLoadingCard(
                    taskTitle: definition.taskTitle,
                    providerName: answers[step.id]?.first ?? "provider",
                    onBack: { cancelProviderResolution() }
                )
            } else if let activeProviderAction, activeProviderAction.stepId == step.id {
                ProviderActionCard(
                    taskTitle: definition.taskTitle,
                    resolution: activeProviderAction.resolution,
                    actionKind: activeProviderAction.kind,
                    userId: userId,
                    showBack: true,
                    onDone: { finishProviderAction(for: step) },
                    onBack: {
                        self.activeProviderAction = nil
                    }
                )
            } else {
                TaskFlowBusinessSearchCard(
                    taskTitle: definition.taskTitle,
                    question: step.question ?? "",
                    placeholder: step.placeholder ?? "Search...",
                    searchHint: step.searchHint ?? "",
                    selectedBusiness: answers[step.id]?.first,
                    showBack: canGoBack,
                    onConfirm: { name in
                        beginProviderResolution(name: name, step: step)
                    },
                    onBack: { goBack() }
                )
            }

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
    /// find-summary text, generalized. "{rowsList}" resolves to the task's
    /// stamped row labels (access flows: "a truck-sized loading spot and
    /// the service elevator window").
    private func summaryBody(for step: FlowStep) -> String {
        var body = step.body ?? ""
        if let variants = step.bodyVariants {
            for variant in variants where conditionsSatisfied(variant.when) {
                body = variant.body
                break
            }
        }
        if body.contains("{rowsList}") {
            let labels = rows.compactMap { step.rowLabels?[$0.id] }
            body = body.replacingOccurrences(of: "{rowsList}", with: labels.joined(separator: " and "))
        }
        return body
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
        guard let nextId, let nextStep = resolvedStep(withId: nextId) else { return }

        path.append(nextId)
        persistProgress()

        // Empty-taskId guard (Phase A validator finding): Firestore's
        // documentWithPath: raises an uncatchable ObjC exception on an empty
        // segment — the harness can run without a task doc.
        if !taskId.isEmpty, let stageRaw = nextStep.stage, let stage = TaskStage(rawValue: stageRaw) {
            let id = taskId
            Task { await actionService.setStage(taskId: id, stage: stage) }
        }
    }

    private func goBack() {
        guard canGoBack else { return }
        path.removeLast()
        persistProgress()
    }

    // MARK: - Provider Resolution

    private func beginProviderResolution(name: String, step: FlowStep) {
        record(step.id, [name])
        guard supportsProviderResolution(step) else {
            advance(from: step, selected: name)
            return
        }

        providerResolveTask?.cancel()
        resolvingProviderStepId = step.id
        let category = providerCategory(for: step)
        let intent = providerIntent(for: step)
        let kind = ProviderActionKind(intent: intent)

        providerResolveTask = Task { @MainActor in
            let resolution = await ProviderDirectoryService.shared.resolve(
                name: name,
                category: category,
                intent: intent
            )
            guard !Task.isCancelled, resolvingProviderStepId == step.id else { return }
            resolvingProviderStepId = nil
            providerResolveTask = nil

            let methodKey = providerMethodKey(for: step)
            if resolution.method == .concierge {
                record(methodKey, ["concierge"])
                advance(from: step, selected: name)
            } else {
                record(methodKey, ["self_service"])
                activeProviderAction = ActiveProviderAction(
                    stepId: step.id,
                    resolution: resolution,
                    kind: kind
                )
            }
        }
    }

    private func cancelProviderResolution() {
        providerResolveTask?.cancel()
        providerResolveTask = nil
        resolvingProviderStepId = nil
    }

    private func finishProviderAction(for step: FlowStep) {
        activeProviderAction = nil
        let nextIsSummary = step.next
            .flatMap { resolvedStep(withId: $0) }?
            .kind == .summary
        let hasConciergeRow = answers.contains { key, value in
            key.hasSuffix(".__provider_method") && value.first == "concierge"
        }

        if nextIsSummary && !hasConciergeRow {
            concludeFlow { onComplete() }
        } else {
            advance(from: step, selected: answers[step.id]?.first)
        }
    }

    private func supportsProviderResolution(_ step: FlowStep) -> Bool {
        switch definition.workflowId {
        case "financial_accounts", "memberships":
            return true
        case "manage_vet", "transfer_pharmacy_records":
            return step.id == "business_name" || step.id == "current_business"
        default:
            return false
        }
    }

    private func providerIntent(for step: FlowStep) -> ProviderIntent {
        switch definition.workflowId {
        case "memberships":
            return inputs.isLongDistance ? .cancel : .transferLocation
        case "manage_vet", "transfer_pharmacy_records":
            return step.id == "current_business" ? .transferRecords : .updateAddress
        default:
            return .updateAddress
        }
    }

    private func providerCategory(for step: FlowStep) -> String {
        switch definition.workflowId {
        case "financial_accounts": "financial"
        case "memberships": "membership"
        default: step.searchHint ?? "account"
        }
    }

    private func providerMethodKey(for step: FlowStep) -> String {
        "\(step.id).__provider_method"
    }

    // MARK: - Answers + Persistence

    private func record(_ key: String, _ values: [String]) {
        answers[key] = values
        persistProgress()
    }

    private func persistProgress() {
        exitCoordinator.persist(
            FlowProgressSnapshot(path: path, answers: answers)
        )
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

        guard !taskId.isEmpty, !userId.isEmpty else {
            rows = []
            resolvedSteps = definition.resolvedSteps(rows: [])
            path = [resolvedSteps.first?.id ?? ""]
            return
        }

        let savedProgress = await exitCoordinator.restore()
        let data: [String: Any]
        do {
            let document = try await Firestore.firestore()
                .collection("users").document(userId)
                .collection("tasks").document(taskId).getDocument()
            data = document.data() ?? [:]
        } catch {
            print("⚠️ Failed to load flow rows: \(error.localizedDescription)")
            data = [:]
        }

        rows = (data["flowRows"] as? [[String: Any]])?
            .compactMap(FlowRow.init(firestoreData:)) ?? []
        resolvedSteps = definition.resolvedSteps(rows: rows)
        let entry = resolvedSteps.first?.id ?? ""

        let savedPath = savedProgress.path
        let savedAnswers = savedProgress.answers

        // A reseed can rename steps; a trail referencing unknown ids restarts.
        let pathIsValid = !savedPath.isEmpty && savedPath.allSatisfy { resolvedStep(withId: $0) != nil }

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
        // Peezy working on the user's behalf is Peezy+ — the hard gate
        // (self-service paths never reach this function and stay free).
        guard PaywallPolicy.allows(.conciergeSubmission) else {
            showPaywallGate = true
            return
        }
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

// MARK: - Flow Engine Loader

/// Router terminal for data-driven flows (Spec 04 Phase C): fetches the
/// definition (cache → direct Firestore → callable fallback) and hands off to
/// the engine. Ids with no definition render the coming-right-up card — the
/// permanent-spinner dead end (old PeezyHomeView behavior) is gone.
struct FlowEngineLoaderView: View {
    let workflowId: String
    let userId: String
    let taskId: String
    let inputs: FlowInputs
    let onComplete: () -> Void
    let onDismiss: () -> Void
    let onStatusAction: (TaskFlowStatusAction) -> Void

    private enum LoadState {
        case loading
        case loaded(FlowDefinition)
        case unavailable
    }

    @State private var state: LoadState = .loading

    var body: some View {
        switch state {
        case .loading:
            ZStack {
                InteractiveBackground()
                    .ignoresSafeArea()
                ProgressView()
                    .tint(PeezyTheme.Colors.deepInk)
            }
            .accessibilityIdentifier("flow.loader.\(workflowId)")
            .task {
                if let definition = await FlowDefinitionStore.shared.definition(for: workflowId) {
                    state = .loaded(definition)
                } else {
                    print("⚠️ No flow definition for '\(workflowId)' — rendering coming-right-up")
                    state = .unavailable
                }
            }

        case .loaded(let definition):
            FlowEngineView(
                definition: definition,
                userId: userId,
                taskId: taskId,
                inputs: inputs,
                onComplete: onComplete,
                onDismiss: onDismiss,
                onStatusAction: onStatusAction
            )

        case .unavailable:
            ComingRightUpCard(onClose: onDismiss)
        }
    }
}

// MARK: - Coming Right Up

/// Graceful terminal for a task the app can't route yet. Closing returns the
/// task to the front of today's queue untouched.
struct ComingRightUpCard: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            InteractiveBackground()
                .ignoresSafeArea()

            TaskFlowStack(cardsRemaining: 1, currentIndex: 0) {
                VStack(spacing: 0) {
                    Spacer()

                    VStack(alignment: .center, spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(PeezyTheme.Colors.deepInk.opacity(0.08))
                            Image(systemName: "sparkles")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(PeezyTheme.Colors.deepInk)
                        }
                        .frame(width: 64, height: 64)

                        Text("Coming right up")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(PeezyTheme.Colors.deepInk)
                            .multilineTextAlignment(.center)

                        Text("This one isn't quite ready in the app — we're on it. It'll stay on your list.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(PeezyTheme.Colors.deepInk.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                    Spacer()

                    PeezyAssessmentButton("Got it") {
                        onClose()
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .accessibilityIdentifier("flow.coming_right_up")
            }
        }
    }
}
