import Observation
import SwiftUI

struct FlowAnswerIdentity: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case mapkit, manual }
    var id: String
    var label: String
    var source: Source
}

struct FlowProgressSnapshot: Equatable, Sendable {
    var path: [String]
    var answers: [String: [String]]
    var answerIdentities: [String: FlowAnswerIdentity] = [:]
    var flowAttemptId: String? = nil

    static let empty = FlowProgressSnapshot(path: [], answers: [:], answerIdentities: [:], flowAttemptId: nil)

    var hasRecordedAnswers: Bool {
        answers.values.contains { !$0.isEmpty }
    }
}

enum FlowAnswerMutationGate {
    /// Terminal submission captures an immutable answer payload. Mutations are
    /// rejected until a pre-terminal submission failure unlocks the flow.
    @discardableResult
    static func apply(
        isSubmitting: Bool,
        isTerminalizing: Bool,
        mutation: () -> Void
    ) -> Bool {
        guard !isSubmitting, !isTerminalizing else { return false }
        mutation()
        return true
    }
}

enum FlowProgressPersistenceError: LocalizedError {
    case missingIdentity

    var errorDescription: String? {
        "This task is missing the identity required to save progress."
    }
}

enum FlowPreSubmitBarrierError: LocalizedError {
    case submissionAlreadyPreparing
    case progressNotRestored
    case persistenceIncomplete
    case persistenceFailed(String?)
    case missingPersistedAttempt
    case persistedAttemptMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .submissionAlreadyPreparing:
            return "This submission is already being prepared."
        case .progressNotRestored:
            return "Saved task progress has not finished loading."
        case .persistenceIncomplete:
            return "Task progress has not finished saving."
        case .persistenceFailed(let message):
            return message ?? "Task progress could not be saved."
        case .missingPersistedAttempt:
            return "The task submission identity has not been saved."
        case .persistedAttemptMismatch:
            return "The saved task submission identity does not match the current task."
        }
    }
}

enum FlowTerminalCleanup {
    /// A terminal edge becomes visible only after the persisted path, answers,
    /// and answer identities have all been removed successfully.
    @MainActor
    static func run(
        clear: () async throws -> Void,
        onSuccess: () -> Void
    ) async throws {
        try await clear()
        onSuccess()
    }
}

enum FlowTerminalSubmissionError: Error {
    case rejected
}

/// Remembers whether this view has observed a successful remote submission so
/// retry errors can use accurate copy. Correctness comes from the durable
/// submission token: every attempt submits the same logical boundary and lets
/// the backend replay its stored result, including after view recreation.
@MainActor
@Observable
final class FlowTerminalSubmissionState {
    private(set) var submissionSucceeded = false

    func run(
        submit: () async throws -> Void,
        clear: () async throws -> Void,
        onSuccess: () -> Void
    ) async throws {
        try await submit()
        submissionSucceeded = true
        try await clear()
        onSuccess()
    }
}

enum FlowPersistenceState: Equatable {
    case restoring
    case idle
    case pending
    case succeeded
    case failed
}

enum FlowExitPrompt: String, Identifiable {
    case saved
    case unsaved

    var id: String { rawValue }
}

@MainActor
@Observable
final class FlowExitCoordinator {
    private(set) var snapshot: FlowProgressSnapshot
    private(set) var persistenceState: FlowPersistenceState = .restoring
    private(set) var lastPersistenceError: String?
    private(set) var isEvaluatingAnswerState = false
    private(set) var isExternalAnswerStateReady: Bool
    private(set) var isTerminalizing = false
    private(set) var isSubmissionLocked = false
    private(set) var persistedFlowAttemptId: String?

    private let userId: String
    private let taskId: String
    private let loadProgress: @MainActor () async throws -> FlowProgressSnapshot
    private let writeProgress: @MainActor (FlowProgressSnapshot) async throws -> Void
    private let generatedFlowAttemptId: String
    private var hasRestored = false
    private var restorationTask: Task<Result<FlowProgressSnapshot, Error>, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var answerProbe: (() async -> Bool)?
    private var hasNewerLocalSnapshot = false

    var isReadyForExit: Bool {
        hasRestored
            && isExternalAnswerStateReady
            && !isEvaluatingAnswerState
            && !isSubmissionLocked
            && !isTerminalizing
    }

    /// Stable for this task/flow lifecycle. Restores the persisted value when
    /// present; legacy tasks adopt and persist the coordinator's generated ID.
    var flowAttemptId: String {
        snapshot.flowAttemptId ?? generatedFlowAttemptId
    }

    /// Exit-lock contract (movers chain, plan v7): a flow sets this while a
    /// spawn/complete edge is in flight and through its confirmation state.
    /// The outer X disables whenever it holds; edge failure must clear it so
    /// the user is never trapped.
    private(set) var isExitLocked = false

    func setExitLocked(_ locked: Bool) {
        guard locked || !isTerminalizing else { return }
        isExitLocked = locked
    }

    init(
        userId: String,
        taskId: String,
        waitsForExternalAnswerState: Bool = false,
        loadProgress: (@MainActor () async throws -> FlowProgressSnapshot)? = nil,
        flowAttemptIdGenerator: @escaping () -> String = { UUID().uuidString },
        writeProgress: (@MainActor (FlowProgressSnapshot) async throws -> Void)? = nil
    ) {
        self.userId = userId
        self.taskId = taskId
        self.isExternalAnswerStateReady = !waitsForExternalAnswerState
        let candidateAttemptId = flowAttemptIdGenerator().trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedFlowAttemptId = candidateAttemptId.isEmpty ? UUID().uuidString : candidateAttemptId
        self.generatedFlowAttemptId = generatedFlowAttemptId
        self.snapshot = FlowProgressSnapshot(
            path: [], answers: [:], answerIdentities: [:], flowAttemptId: generatedFlowAttemptId
        )
        let actionService = TaskActionService()
        self.loadProgress = loadProgress ?? {
            try await actionService.loadFlowProgress(userId: userId, taskId: taskId)
        }
        self.writeProgress = writeProgress ?? { snapshot in
            try await actionService.writeFlowProgress(
                userId: userId,
                taskId: taskId,
                path: snapshot.path,
                answers: snapshot.answers,
                answerIdentities: snapshot.answerIdentities,
                flowAttemptId: snapshot.flowAttemptId
            )
        }
    }

    func restore() async -> FlowProgressSnapshot {
        if hasRestored { return snapshot }

        if taskId.isEmpty || userId.isEmpty {
            hasRestored = true
            persistenceState = .idle
            return snapshot
        }

        if restorationTask == nil {
            let loadProgress = loadProgress
            restorationTask = Task {
                do {
                    return .success(try await loadProgress())
                } catch {
                    return .failure(error)
                }
            }
        }

        guard let result = await restorationTask?.value else { return snapshot }
        restorationTask = nil
        hasRestored = true

        switch result {
        case .success(let restored):
            if !hasNewerLocalSnapshot {
                var restored = restored
                let persistedAttemptId = restored.flowAttemptId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let requiresAttemptMigration = persistedAttemptId?.isEmpty != false
                    || persistedAttemptId != restored.flowAttemptId
                restored.flowAttemptId = requiresAttemptMigration
                    ? generatedFlowAttemptId
                    : persistedAttemptId
                snapshot = restored
                persistedFlowAttemptId = requiresAttemptMigration ? nil : persistedAttemptId
                persistenceState = restored.hasRecordedAnswers ? .succeeded : .idle
                lastPersistenceError = nil
                if requiresAttemptMigration {
                    persist(restored)
                }
            }
        case .failure(let error):
            if !hasNewerLocalSnapshot {
                persistenceState = .failed
                lastPersistenceError = error.localizedDescription
            }
        }
        return snapshot
    }

    func persist(_ newSnapshot: FlowProgressSnapshot) {
        guard !isSubmissionLocked, !isTerminalizing else { return }
        var newSnapshot = newSnapshot
        newSnapshot.flowAttemptId = flowAttemptId
        hasNewerLocalSnapshot = true
        snapshot = newSnapshot
        guard !taskId.isEmpty, !userId.isEmpty else {
            if newSnapshot.hasRecordedAnswers {
                persistenceState = .failed
                lastPersistenceError = "Missing user or task identity"
            }
            return
        }

        persistenceGeneration += 1
        let generation = persistenceGeneration
        let precedingTask = persistenceTask
        let writeProgress = writeProgress

        persistenceState = .pending
        lastPersistenceError = nil
        persistenceTask = Task { [weak self] in
            await precedingTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await writeProgress(newSnapshot)
                guard !Task.isCancelled else { return }
                self?.finishPersistence(
                    generation: generation,
                    error: nil,
                    persistedAttemptId: newSnapshot.flowAttemptId
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishPersistence(generation: generation, error: error)
            }
        }
    }

    /// Locks navigation and progress mutation before a terminal callable can
    /// begin, drains every already-queued write, then proves that the exact
    /// lifecycle attempt used by the callable is durably stored.
    ///
    /// The lock is acquired synchronously so a second UI event cannot enqueue
    /// progress between capturing the queue and starting the returned task.
    func beginPreSubmitBarrier() -> Task<String, Error> {
        if isSubmissionLocked {
            if isTerminalizing {
                let queuedPersistence = persistenceTask
                let expectedAttemptId = flowAttemptId
                return Task { @MainActor [weak self] in
                    await queuedPersistence?.value
                    guard let self else {
                        throw FlowPreSubmitBarrierError.persistenceIncomplete
                    }
                    try self.validatePersistedAttempt(expectedAttemptId)
                    return expectedAttemptId
                }
            }
            return Task {
                throw FlowPreSubmitBarrierError.submissionAlreadyPreparing
            }
        }

        isSubmissionLocked = true
        isExitLocked = true
        let queuedPersistence = persistenceTask
        let expectedAttemptId = flowAttemptId

        return Task { @MainActor [weak self] in
            await queuedPersistence?.value
            guard let self else {
                throw FlowPreSubmitBarrierError.persistenceIncomplete
            }
            do {
                try self.validatePersistedAttempt(expectedAttemptId)
                return expectedAttemptId
            } catch {
                self.releaseSubmissionLockAfterFailure()
                throw error
            }
        }
    }

    /// A failed pre-terminal persistence or callable restores normal editing
    /// and exit behavior. Once terminal cleanup begins, the lock is permanent
    /// until that cleanup succeeds and the flow disappears.
    func releaseSubmissionLockAfterFailure() {
        guard !isTerminalizing else { return }
        isSubmissionLocked = false
        isExitLocked = false
    }

    /// Starts the irreversible terminal edge synchronously on the main actor.
    /// New progress is rejected from this point forward and the outer exit
    /// remains locked even when clearing fails.
    func beginTerminalization() {
        isSubmissionLocked = true
        isTerminalizing = true
        isExitLocked = true
    }

    /// Drains the full serialized persistence chain before removing its fields.
    /// A failed clear leaves the coordinator terminalizing, so retry cannot
    /// enqueue or race a write behind the successful deletion.
    func terminalize(clear: () async throws -> Void) async throws {
        beginTerminalization()
        let queuedPersistence = persistenceTask
        await queuedPersistence?.value
        try await clear()
    }

    func registerAnswerProbe(_ probe: @escaping () async -> Bool) {
        answerProbe = probe
    }

    func noteExternalAnswerStateReady() {
        isExternalAnswerStateReady = true
    }

    func noteExternalPersistencePending() {
        guard !isSubmissionLocked, !isTerminalizing else { return }
        supersedeGenericPersistence()
        hasNewerLocalSnapshot = true
        persistenceState = .pending
        lastPersistenceError = nil
    }

    func noteExternalPersistenceFailure(_ error: Error) {
        guard !isSubmissionLocked, !isTerminalizing else { return }
        supersedeGenericPersistence()
        hasNewerLocalSnapshot = true
        persistenceState = .failed
        lastPersistenceError = error.localizedDescription
    }

    func noteExternallyPersistedAnswer(
        path: [String],
        answers: [String: [String]]
    ) {
        guard !isSubmissionLocked, !isTerminalizing else { return }
        supersedeGenericPersistence()
        hasNewerLocalSnapshot = true
        snapshot = FlowProgressSnapshot(
            path: path,
            answers: answers,
            answerIdentities: snapshot.answerIdentities,
            flowAttemptId: flowAttemptId
        )
        persistenceState = .succeeded
        lastPersistenceError = nil
    }

    func unregisterAnswerProbe() {
        answerProbe = nil
    }

    func exitPrompt() async -> FlowExitPrompt? {
        guard isReadyForExit else { return nil }
        isEvaluatingAnswerState = true
        let probedAnswer = await answerProbe?() ?? false
        isEvaluatingAnswerState = false

        guard snapshot.hasRecordedAnswers || probedAnswer else {
            return nil
        }
        return persistenceState == .succeeded ? .saved : .unsaved
    }

    private func finishPersistence(
        generation: Int,
        error: Error?,
        persistedAttemptId: String? = nil
    ) {
        if error == nil, let persistedAttemptId {
            persistedFlowAttemptId = persistedAttemptId
        }
        guard generation == persistenceGeneration else { return }
        if let error {
            persistenceState = .failed
            lastPersistenceError = error.localizedDescription
        } else {
            persistenceState = .succeeded
            lastPersistenceError = nil
        }
    }

    private func validatePersistedAttempt(_ expectedAttemptId: String) throws {
        guard hasRestored else {
            throw FlowPreSubmitBarrierError.progressNotRestored
        }
        switch persistenceState {
        case .restoring, .pending:
            throw FlowPreSubmitBarrierError.persistenceIncomplete
        case .failed:
            throw FlowPreSubmitBarrierError.persistenceFailed(lastPersistenceError)
        case .idle, .succeeded:
            break
        }
        guard let persistedFlowAttemptId else {
            throw FlowPreSubmitBarrierError.missingPersistedAttempt
        }
        guard persistedFlowAttemptId == expectedAttemptId else {
            throw FlowPreSubmitBarrierError.persistedAttemptMismatch(
                expected: expectedAttemptId,
                actual: persistedFlowAttemptId
            )
        }
    }

    private func supersedeGenericPersistence() {
        persistenceGeneration += 1
        persistenceTask?.cancel()
    }
}

struct OutermostTaskFlowContainer<Content: View>: View {
    let onDismiss: () -> Void
    private let content: (@escaping () -> Void) -> Content

    @State private var coordinator: FlowExitCoordinator
    @State private var prompt: FlowExitPrompt?

    init(
        userId: String,
        taskId: String,
        waitsForExternalAnswerState: Bool = false,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> Content
    ) {
        self.onDismiss = onDismiss
        self.content = content
        _coordinator = State(
            initialValue: FlowExitCoordinator(
                userId: userId,
                taskId: taskId,
                waitsForExternalAnswerState: waitsForExternalAnswerState
            )
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content(requestExit)
                .environment(coordinator)

            Button(action: requestExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(PeezyTheme.Colors.deepInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close task")
            .accessibilityIdentifier("flow.exit")
            .padding(.top, 8)
            .padding(.trailing, 12)
            .disabled(!coordinator.isReadyForExit || coordinator.isExitLocked)
            .zIndex(100)
        }
        .task {
            _ = await coordinator.restore()
        }
        .alert(
            "Leave this task?",
            isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            ),
            presenting: prompt
        ) { prompt in
            Button(prompt == .saved ? "Leave" : "Leave anyway", role: .destructive) {
                self.prompt = nil
                onDismiss()
            }
            Button("Keep going", role: .cancel) {
                self.prompt = nil
            }
        } message: { prompt in
            Text(
                prompt == .saved
                    ? "Your answers are saved. Pick up where you left off anytime."
                    : "We couldn't save your last answer — check your connection before leaving."
            )
        }
    }

    private func requestExit() {
        guard coordinator.isReadyForExit, !coordinator.isExitLocked else { return }
        Task { @MainActor in
            if let prompt = await coordinator.exitPrompt() {
                self.prompt = prompt
            } else {
                onDismiss()
            }
        }
    }
}
