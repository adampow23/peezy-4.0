import Observation
import SwiftUI

struct FlowProgressSnapshot: Equatable, Sendable {
    var path: [String]
    var answers: [String: [String]]

    static let empty = FlowProgressSnapshot(path: [], answers: [:])

    var hasRecordedAnswers: Bool {
        answers.values.contains { !$0.isEmpty }
    }
}

enum FlowProgressPersistenceError: LocalizedError {
    case missingIdentity

    var errorDescription: String? {
        "This task is missing the identity required to save progress."
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
    private(set) var snapshot = FlowProgressSnapshot.empty
    private(set) var persistenceState: FlowPersistenceState = .restoring
    private(set) var lastPersistenceError: String?
    private(set) var isEvaluatingAnswerState = false
    private(set) var isExternalAnswerStateReady: Bool

    private let userId: String
    private let taskId: String
    private let actionService: TaskActionService
    private var hasRestored = false
    private var restorationTask: Task<Result<FlowProgressSnapshot, Error>, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var answerProbe: (() async -> Bool)?
    private var hasNewerLocalSnapshot = false

    var isReadyForExit: Bool {
        hasRestored && isExternalAnswerStateReady && !isEvaluatingAnswerState
    }

    init(
        userId: String,
        taskId: String,
        waitsForExternalAnswerState: Bool = false
    ) {
        self.userId = userId
        self.taskId = taskId
        self.isExternalAnswerStateReady = !waitsForExternalAnswerState
        self.actionService = TaskActionService()
    }

    func restore() async -> FlowProgressSnapshot {
        if hasRestored { return snapshot }

        if taskId.isEmpty || userId.isEmpty {
            hasRestored = true
            persistenceState = .idle
            return snapshot
        }

        if restorationTask == nil {
            let service = actionService
            let uid = userId
            let id = taskId
            restorationTask = Task {
                do {
                    return .success(try await service.loadFlowProgress(userId: uid, taskId: id))
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
                snapshot = restored
                persistenceState = restored.hasRecordedAnswers ? .succeeded : .idle
                lastPersistenceError = nil
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
        let service = actionService
        let uid = userId
        let id = taskId

        persistenceState = .pending
        lastPersistenceError = nil
        persistenceTask = Task { [weak self] in
            await precedingTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await service.writeFlowProgress(
                    userId: uid,
                    taskId: id,
                    path: newSnapshot.path,
                    answers: newSnapshot.answers
                )
                guard !Task.isCancelled else { return }
                self?.finishPersistence(generation: generation, error: nil)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishPersistence(generation: generation, error: error)
            }
        }
    }

    func registerAnswerProbe(_ probe: @escaping () async -> Bool) {
        answerProbe = probe
    }

    func noteExternalAnswerStateReady() {
        isExternalAnswerStateReady = true
    }

    func noteExternalPersistencePending() {
        supersedeGenericPersistence()
        hasNewerLocalSnapshot = true
        persistenceState = .pending
        lastPersistenceError = nil
    }

    func noteExternalPersistenceFailure(_ error: Error) {
        supersedeGenericPersistence()
        hasNewerLocalSnapshot = true
        persistenceState = .failed
        lastPersistenceError = error.localizedDescription
    }

    func noteExternallyPersistedAnswer(
        path: [String],
        answers: [String: [String]]
    ) {
        supersedeGenericPersistence()
        hasNewerLocalSnapshot = true
        snapshot = FlowProgressSnapshot(path: path, answers: answers)
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

    private func finishPersistence(generation: Int, error: Error?) {
        guard generation == persistenceGeneration else { return }
        if let error {
            persistenceState = .failed
            lastPersistenceError = error.localizedDescription
        } else {
            persistenceState = .succeeded
            lastPersistenceError = nil
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
            .disabled(!coordinator.isReadyForExit)
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
        guard coordinator.isReadyForExit else { return }
        Task { @MainActor in
            if let prompt = await coordinator.exitPrompt() {
                self.prompt = prompt
            } else {
                onDismiss()
            }
        }
    }
}
