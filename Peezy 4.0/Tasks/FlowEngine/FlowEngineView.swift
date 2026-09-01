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
    @State private var answerIdentities: [String: FlowAnswerIdentity] = [:]
    /// Rows stamped on the task doc by generation (flowRows) and the
    /// definition's steps specialized to them (Spec 04 Phase B).
    @State private var rows: [FlowRow] = []
    @State private var resolvedSteps: [FlowStep] = []
    @State private var isSubmitting = false
    @State private var isRestoring = true
    @State private var resolvingProviderStepId: String?
    @State private var activeProviderAction: ActiveProviderAction?
    @State private var providerResolveTask: Task<Void, Never>?
    @State private var submissionError: String?
    @State private var terminalCleanupError: String?
    @State private var submissionAttempt = 0
    @State private var terminalSubmissionState = FlowTerminalSubmissionState()
    /// Set on spawnTasks success; flips the spawn card into its confirmation
    /// rendering (returned titles + scheduled dates, Done → conclude).
    @State private var spawnedTasks: [SpawnService.SpawnedTask]?
    @State private var pendingPostFlowCompletion: PostFlowCompletion?
    @State private var researchConfiguration: TaskResearchConfiguration?
    @State private var isRoutingPostFlow = false

    private enum PostFlowCompletion: String, Identifiable {
        case complete
        case statusDone

        var id: String { rawValue }
    }

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
            async let loadedResearchConfiguration = TaskResearchConfiguration.load(
                userId: userId,
                taskDocumentId: taskId,
                fallbackCatalogTaskId: definition.workflowId
            )
            await restoreState()
            researchConfiguration = await loadedResearchConfiguration
        }
        .onDisappear {
            providerResolveTask?.cancel()
        }
        .fullScreenCover(item: $pendingPostFlowCompletion) { completion in
            if let researchConfiguration {
                PostFlowForkView(
                    userId: userId,
                    configuration: researchConfiguration,
                    flowAnswers: answers,
                    onComplete: { finishPostFlow(completion) }
                )
                .interactiveDismissDisabled()
            }
        }
        .alert(
            "Couldn't finish this task",
            isPresented: Binding(
                get: { terminalCleanupError != nil },
                set: { if !$0 { terminalCleanupError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { terminalCleanupError = nil }
        } message: {
            Text(terminalCleanupError ?? "Check your connection, then try again.")
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

    private var canGoBack: Bool {
        path.count > 1 && !isSubmitting && !exitCoordinator.isTerminalizing
    }

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
                question: step.question ?? "Would guided next steps help with this?",
                questionIcon: PeezyQuestionVisuals.flowIcon(
                    workflowID: definition.workflowId,
                    stepID: step.id
                ),
                yesLabel: "Show me how",
                noLabel: "I have a plan",
                timeSaved: "time",
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
                    selectedBusiness: answerIdentities[step.id],
                    showBack: canGoBack,
                    onConfirm: { identity in
                        answerIdentities[step.id] = identity
                        record(step.id, [identity.label])
                        beginProviderResolution(name: identity.label, step: step)
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
                bodyText: actionSheetBody,
                primaryLabel: submissionError == nil ? "Done" : "Try again",
                subtext: submissionError ?? "Use this action sheet while you make the calls or complete the steps.",
                showBack: canGoBack,
                onPrimary: { submitAndComplete() },
                onBack: { goBack() }
            )
            .id("summary.\(submissionAttempt)")

        case .status:
            TaskFlowStatusCard(
                taskTitle: definition.taskTitle,
                showBack: canGoBack,
                onLater: { concludeFlow { onStatusAction(.later) } },
                onInProgress: { concludeFlow { onStatusAction(.inProgress) } },
                onDone: {
                    concludeFlow {
                        beginPostFlow(.statusDone)
                    }
                },
                onBack: { goBack() }
            )

        case .spawn:
            TaskFlowSummaryCard(
                taskTitle: definition.taskTitle,
                bodyText: spawnBody(for: step),
                primaryLabel: spawnPrimaryLabel(for: step),
                subtext: submissionError ?? step.subtext ?? "Peezy schedules these so nothing slips.",
                showBack: spawnedTasks == nil && canGoBack,
                onPrimary: { spawnPrimaryTapped(step) },
                onBack: { goBack() }
            )
            .id("spawn.\(submissionAttempt).\(spawnedTasks != nil)")
        }
    }

    private var actionSheetBody: String {
        var sections = ["You're set. Here's everything you need."]

        let contacts = resolvedSteps
            .filter { $0.kind == .businessSearch }
            .compactMap { answers[$0.id]?.first }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !contacts.isEmpty {
            sections.append("Who to contact\n" + contacts.map { "• \($0)" }.joined(separator: "\n"))
            sections.append("What to say\n“Hi, I'm moving and need to complete this change. What steps, dates, and documents do you need from me?”")
        }

        let answerLines = resolvedSteps.compactMap { step -> String? in
            guard step.kind != .title,
                  step.kind != .summary,
                  step.kind != .status,
                  step.kind != .businessSearch,
                  let values = answers[step.id],
                  !values.isEmpty,
                  !step.id.hasSuffix(".__provider_method") else { return nil }

            let prompt = (step.kind == .decision ? "Handling" : (step.infoTitle ?? humanized(step.id)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayValues = values.map { displayValue($0, for: step) }.sorted()
            return "• \(prompt): \(displayValues.joined(separator: ", "))"
        }
        if !answerLines.isEmpty {
            sections.append("What to have ready\n" + answerLines.joined(separator: "\n"))
        }

        if contacts.isEmpty && answerLines.isEmpty {
            sections.append("Next step\nUse the guidance above to contact the provider or complete the task directly.")
        }
        return sections.joined(separator: "\n\n")
    }

    private func displayValue(_ value: String, for step: FlowStep) -> String {
        if let label = step.options?.first(where: { $0.id == value })?.label {
            return label
        }
        switch value {
        case "peezy":
            return "Guided next steps"
        case "self":
            return "Handle directly"
        default:
            if step.kind == .confirmDate,
               let date = ISO8601DateFormatter().date(from: value) {
                return date.formatted(date: .abbreviated, time: .omitted)
            }
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func humanized(_ value: String) -> String {
        value
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
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
        let landingId = resolveKnownAnswerSkips(from: nextId)
        guard let landingId, let nextStep = resolvedStep(withId: landingId) else { return }

        path.append(landingId)
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
            record(methodKey, [resolution.method.rawValue])
            activeProviderAction = ActiveProviderAction(
                stepId: step.id,
                resolution: resolution,
                kind: kind
            )
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
            concludeFlow {
                beginPostFlow(.complete)
            }
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
            FlowProgressSnapshot(path: path, answers: answers, answerIdentities: answerIdentities)
        )
    }

    /// Clears persisted flow state, then fires the terminal callback —
    /// status-card exits (later / in progress / done).
    private func concludeFlow(_ callback: @escaping () -> Void) {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil
        terminalCleanupError = nil
        exitCoordinator.beginTerminalization()
        let id = taskId
        Task { @MainActor in
            do {
                try await FlowTerminalCleanup.run(
                    clear: {
                        try await exitCoordinator.terminalize {
                            try await actionService.clearFlowState(taskId: id)
                        }
                    },
                    onSuccess: {
                        isSubmitting = false
                        callback()
                    }
                )
            } catch {
                isSubmitting = false
                let message = "Your progress is still saved. Check your connection, then try finishing again."
                submissionError = message
                terminalCleanupError = message
                submissionAttempt += 1
            }
        }
    }

    private func finishPostFlow(_ completion: PostFlowCompletion) {
        pendingPostFlowCompletion = nil
        isRoutingPostFlow = false
        isSubmitting = false
        switch completion {
        case .complete:
            onComplete()
        case .statusDone:
            onStatusAction(.done)
        }
    }

    private func beginPostFlow(_ completion: PostFlowCompletion) {
        guard !isRoutingPostFlow else { return }
        isRoutingPostFlow = true
        isSubmitting = true

        if let researchConfiguration {
            routePostFlow(completion, configuration: researchConfiguration)
            return
        }

        Task {
            let configuration = await TaskResearchConfiguration.load(
                userId: userId,
                taskDocumentId: taskId,
                fallbackCatalogTaskId: definition.workflowId
            )
            await MainActor.run {
                researchConfiguration = configuration
                routePostFlow(completion, configuration: configuration)
            }
        }
    }

    private func routePostFlow(
        _ completion: PostFlowCompletion,
        configuration: TaskResearchConfiguration
    ) {
        if TaskResearchPolicy.isEligible(
            configuration: configuration,
            flowAnswers: answers
        ) {
            pendingPostFlowCompletion = completion
        } else {
            finishPostFlow(completion)
        }
    }

    // MARK: - Known Answers (Spec 09 Phase 4)

    /// Instance wrapper over the pure walk: adopts remembered values into the
    /// live answer state and returns the first step id that must render.
    private func resolveKnownAnswerSkips(from id: String?) -> String? {
        Self.resolveKnownAnswerSkips(
            from: id,
            steps: resolvedSteps,
            knownAnswers: MoveAnswersStore.shared.answers,
            answers: &answers
        )
    }

    /// Pure skipIfKnown walk shared with unit tests: while the target step
    /// declares skipIfKnown and the remembered move answers contain that key,
    /// the value is adopted as the step's answer and the walk follows the
    /// step's branches/next with advance's first-match semantics.
    nonisolated static func resolveKnownAnswerSkips(
        from id: String?,
        steps: [FlowStep],
        knownAnswers: [String: String],
        answers: inout [String: [String]]
    ) -> String? {
        var currentId = id
        var hops = 0
        while hops <= steps.count,
              let stepId = currentId,
              let step = steps.first(where: { $0.id == stepId }),
              let key = step.skipIfKnown,
              let known = knownAnswers[key] {
            hops += 1
            answers[stepId] = [known]
            let recorded = answers
            let branch = step.branches?.first { candidate in
                candidate.value == known &&
                    (candidate.when ?? [:]).allSatisfy { recorded[$0.key]?.first == $0.value }
            }
            currentId = branch?.next ?? step.next
        }
        return currentId
    }

    // MARK: - Spawn Terminal (Spec 09 Phase 4)

    private func spawnPrimaryLabel(for step: FlowStep) -> String {
        if spawnedTasks != nil { return "Done" }
        if submissionError != nil { return "Try again" }
        if resolvedSpawns(for: step).isEmpty { return "Done" }
        return step.primaryLabel ?? "Set it up"
    }

    private func spawnBody(for step: FlowStep) -> String {
        if let spawnedTasks {
            guard !spawnedTasks.isEmpty else {
                return "You're all set — nothing else needed here."
            }
            let lines = spawnedTasks.map { task in
                "• \(task.title)\n   Scheduled for \(formattedSpawnDate(task.dueDateISO))"
            }
            return "Added to your plan:\n\n" + lines.joined(separator: "\n")
        }

        let resolved = resolvedSpawns(for: step)
        guard !resolved.isEmpty else {
            return step.body ?? "You're all set — nothing else needed here."
        }
        let intro = step.body ?? "Here's what Peezy will set up:"
        return intro + "\n\n" + resolved.map { "• \(pendingSpawnTitle(for: $0))" }.joined(separator: "\n")
    }

    /// Pre-submit display title; the server's templated title replaces it in
    /// the confirmation body once the callable returns.
    private func pendingSpawnTitle(for spawn: SpawnService.Spawn) -> String {
        if let institution = spawn.titleParams?["institution"] {
            return "Update \(institution)"
        }
        return humanized(spawn.taskId.lowercased())
    }

    private func formattedSpawnDate(_ iso: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        return date?.formatted(date: .abbreviated, time: .omitted) ?? iso
    }

    private func resolvedSpawns(for step: FlowStep) -> [SpawnService.Spawn] {
        Self.resolveSpawns(
            step.spawns ?? [],
            answers: answers,
            answerIdentities: answerIdentities,
            steps: resolvedSteps
        )
    }

    /// Pure spawn-list resolution shared with unit tests. `when` guards reuse
    /// the branch `when` semantics against recorded answers; `perSelectionFrom`
    /// expands one spawn per selected option with the option's label as
    /// titleParams.institution. Zero resolved spawns is a valid outcome.
    nonisolated static func resolveSpawns(
        _ spawns: [FlowSpawnDef],
        answers: [String: [String]],
        answerIdentities: [String: FlowAnswerIdentity] = [:],
        steps: [FlowStep]
    ) -> [SpawnService.Spawn] {
        spawns.flatMap { def -> [SpawnService.Spawn] in
            if let when = def.when,
               !when.allSatisfy({ answers[$0.key]?.first == $0.value }) {
                return []
            }
            guard let sourceId = def.perSelectionFrom else {
                return [SpawnService.Spawn(taskId: def.taskId)]
            }
            let sources = steps.filter { $0.id == sourceId || $0.id.hasSuffix(".\(sourceId)") }
            return sources.flatMap { source -> [SpawnService.Spawn] in
                let options = source.options ?? []
                return (answers[source.id] ?? []).map { selection in
                    let identity = answerIdentities[source.id]
                    let institutionId = identity?.id ?? selection
                    let label = identity?.label ?? options.first { $0.id == selection }?.label ?? selection
                    let subjectId = source.rowSubjectId ?? selection
                    return SpawnService.Spawn(
                        taskId: def.taskId,
                        titleParams: ["institution": label],
                        subject: .init(kind: "service", id: subjectId),
                        institutionId: institutionId,
                        institution: label
                    )
                }
            }
        }
    }

    private func spawnPrimaryTapped(_ step: FlowStep) {
        if spawnedTasks != nil {
            concludeFlow {
                beginPostFlow(.complete)
            }
            return
        }
        let resolved = resolvedSpawns(for: step)
        // Zero resolved spawns: nothing to create — the callable is not called.
        guard !resolved.isEmpty else {
            concludeFlow {
                beginPostFlow(.complete)
            }
            return
        }
        submitSpawns(resolved)
    }

    private func submitSpawns(_ spawns: [SpawnService.Spawn]) {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil

        // spawnTasks merge-writes answers into moveAnswers/answers — single
        // selections flatten to the store's flat-string contract.
        let collected: [String: Any] = answers.mapValues { value -> Any in
            value.count == 1 ? value[0] : value
        }
        let token = "\(taskId)-spawn"
        let sourceId = taskId.isEmpty ? definition.workflowId : taskId

        Task {
            do {
                let response = try await SpawnService().spawn(
                    token: token,
                    source: SpawnService.Source(kind: "conversation", id: sourceId),
                    spawns: spawns,
                    answers: collected
                )
                await MainActor.run {
                    isSubmitting = false
                    spawnedTasks = response.created
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionError = "Couldn't set that up. Check your connection, then try again."
                    submissionAttempt += 1
                }
            }
        }
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
        await MoveAnswersStore.shared.load(userId: userId)
        let entry = resolvedSteps.first?.id ?? ""

        let savedPath = savedProgress.path
        let savedAnswers = savedProgress.answers
        var savedIdentities = savedProgress.answerIdentities

        // Additive one-time migration for pre-identity business-search answers.
        var migratedIdentity = false
        for step in resolvedSteps where step.kind == .businessSearch {
            if savedIdentities[step.id] == nil, let label = savedAnswers[step.id]?.first, !label.isEmpty {
                savedIdentities[step.id] = BusinessSearchIdentity.makeManual(label: label, existing: nil)
                migratedIdentity = true
            }
        }

        // A reseed can rename steps; a trail referencing unknown ids restarts.
        let pathIsValid = !savedPath.isEmpty && savedPath.allSatisfy { resolvedStep(withId: $0) != nil }

        if pathIsValid {
            path = savedPath
            answers = savedAnswers
            answerIdentities = savedIdentities
            if migratedIdentity { persistProgress() }
        } else {
            path = [resolveKnownAnswerSkips(from: entry) ?? entry]
        }
    }

    // MARK: - Submission (summary terminal)

    private func submitAndComplete() {
        guard !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil
        let preSubmitBarrier = exitCoordinator.beginPreSubmitBarrier()

        var workflowAnswers = WorkflowAnswers(workflowId: definition.workflowId)
        workflowAnswers.answers = answers

        let id = taskId
        Task { @MainActor in
            do {
                let persistedFlowAttemptId = try await preSubmitBarrier.value
                try await terminalSubmissionState.run(
                    submit: {
                        let response = try await WorkflowService().submitAnswers(
                            workflowId: definition.workflowId,
                            answers: workflowAnswers,
                            userId: userId,
                            submissionToken: WorkflowSubmissionToken.make(
                                userId: userId,
                                taskId: taskId,
                                workflowId: definition.workflowId,
                                flowAttemptId: persistedFlowAttemptId
                            )
                        )
                        guard response.success else { throw FlowTerminalSubmissionError.rejected }
                    },
                    clear: {
                        exitCoordinator.beginTerminalization()
                        try await exitCoordinator.terminalize {
                            try await actionService.clearFlowState(taskId: id)
                        }
                    },
                    onSuccess: { beginPostFlow(.complete) }
                )
            } catch {
                isSubmitting = false
                exitCoordinator.releaseSubmissionLockAfterFailure()
                if terminalSubmissionState.submissionSucceeded {
                    let message = "Your answers were saved, but the completed flow couldn't be cleared. Check your connection, then try again."
                    submissionError = message
                    terminalCleanupError = message
                } else {
                    submissionError = "Couldn't save your answers. Check your connection, then try again."
                }
                submissionAttempt += 1
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

                        Text("This one isn't ready in the app yet. It will stay on your task list.")
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
