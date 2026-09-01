//
//  PeezyHomeViewModel.swift
//  Peezy
//
//  State machine view model for the main home screen.
//  States: loading → welcome → task → done
//
//  CRASH FIX: taskFlowWorkflowId cleared only in cleanupTaskFlow().
//  SPINNER FIX: pendingAdvance defers next task until onDismiss fires.
//

import SwiftUI
import Observation
import FirebaseFirestore
import FirebaseAuth

enum NudgeAnswerPhase: Equatable {
    case preSpawn
    case postSpawn
    case claim
}

enum NudgeAnswerState: Equatable {
    case idle
    case inFlight(NudgeChoice)
    case failed(NudgeChoice, NudgeAnswerPhase)
}

protocol NudgeSpawnClient {
    func spawn(
        token: String,
        source: SpawnService.Source,
        spawns: [SpawnService.Spawn],
        answers: [String: Any]?,
        expectedUserId: String?
    ) async throws -> SpawnService.Response
}

extension SpawnService: NudgeSpawnClient {}

struct PeezyHomeTaskProjection: Equatable {
    var actionableLegacy: [PeezyCard]
    var userInProgressLegacy: [PeezyCard]
    var readOnlyContractStatus: [PeezyCard]
}

protocol NudgeAnswerClock {
    func sleep(for duration: Duration) async throws
}

struct SystemNudgeAnswerClock: NudgeAnswerClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

private enum NudgeAnswerOperationError: LocalizedError {
    case missingAuthentication
    case missingTaskID
    case missingSpawnID
    case timedOut

    var errorDescription: String? {
        switch self {
        case .missingAuthentication:
            return "Please sign in again before answering this card."
        case .missingTaskID:
            return "This nudge is missing the task identity needed to save your answer."
        case .missingSpawnID:
            return "This nudge is missing the task it should create."
        case .timedOut:
            return "That took too long. Your card is still here — try the same answer again."
        }
    }
}

private final class NudgeTimeoutResolver<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isResolved = false

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func install(operationTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        guard !isResolved else {
            operationTask.cancel()
            timeoutTask.cancel()
            return
        }
        self.operationTask = operationTask
        self.timeoutTask = timeoutTask
    }

    func resolve(_ result: Result<Value, Error>) {
        guard !isResolved, let continuation else { return }
        isResolved = true
        self.continuation = nil
        operationTask?.cancel()
        timeoutTask?.cancel()
        operationTask = nil
        timeoutTask = nil
        continuation.resume(with: result)
    }
}

@Observable
final class PeezyHomeViewModel {

    // MARK: - State Machine

    enum HomeState {
        case loading
        case firstTimeWelcome
        case dailyGreeting
        case returningMidDay
        case activeTask
        case dailyComplete
        case allComplete
    }

    var state: HomeState = .loading
    var error: String?

    // MARK: - Task Queue

    var taskQueue: [PeezyCard] = []
    var currentTask: PeezyCard?
    var completedThisSession: Int = 0
    private(set) var nudgeAnswerState: NudgeAnswerState = .idle
    private(set) var nudgeAnswerError: String?

    // MARK: - Daily Dose State

    var allActiveTasks: [PeezyCard] = []
    var readOnlyContractStatus: [PeezyCard] = []
    var inProgressTaskCount: Int = 0
    var userInProgressTaskCount: Int = 0
    var gettingAhead: Bool = false
    var isFocusedTask: Bool = false
    var currentBatchOffset: Int = 0

    // MARK: - User Context

    var userState: UserState?

    // MARK: - UserDefaults Keys

    private var userId: String { Auth.auth().currentUser?.uid ?? "anon" }
    private var kDailyDoseCompletedCount: String { dailyDoseCompletedKey(for: userId) }
    private var kDailyDoseLastDate: String { dailyDoseLastDateKey(for: userId) }
    private var kDailyDoseFirstLaunchDate: String { dailyDoseFirstLaunchDateKey(for: userId) }
    private var kHasSeenFirstTimeWelcome: String { hasSeenFirstTimeWelcomeKey(for: userId) }
    private var kLastGreetingDate: String { lastGreetingDateKey(for: userId) }
    private var kTotalCompletedCount: String { totalCompletedKey(for: userId) }

    var totalCompletedCount: Int {
        get { UserDefaults.standard.integer(forKey: kTotalCompletedCount) }
        set { UserDefaults.standard.set(newValue, forKey: kTotalCompletedCount) }
    }

    private let transactionRunner: any TransactionRunner
    private let spawnClient: any NudgeSpawnClient
    private let uidProvider: () -> String?
    private let nudgeClock: any NudgeAnswerClock
    private let spawnTimeout: Duration
    private let claimTimeout: Duration

    private struct NudgeOperation {
        let task: PeezyCard
        let choice: NudgeChoice
        let userId: String?
        let opId: String
        let token: String
        var hasCredited = false
    }

    private var nudgeOperation: NudgeOperation?

    init(
        transactionRunner: any TransactionRunner = FirestoreTransactionRunner(),
        spawnClient: any NudgeSpawnClient = SpawnService(),
        uidProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid },
        clock: any NudgeAnswerClock = SystemNudgeAnswerClock(),
        spawnTimeout: Duration = .seconds(15),
        claimTimeout: Duration = .seconds(10)
    ) {
        self.transactionRunner = transactionRunner
        self.spawnClient = spawnClient
        self.uidProvider = uidProvider
        self.nudgeClock = clock
        self.spawnTimeout = spawnTimeout
        self.claimTimeout = claimTimeout
    }

    // MARK: - Task Flow System

    var showTaskFlow = false
    var taskFlowWorkflowId: String?
    private var pendingAdvance = false

    func cleanupTaskFlow() {
        taskFlowWorkflowId = nil
        if pendingAdvance {
            pendingAdvance = false
            advanceAfterTask()
        }
    }

    /// Workflow-backed cards and explicit router mappings enter their flow.
    /// A nil route keeps off-app/static cards on the task-detail surface.
    private func flowId(for card: PeezyCard) -> String? {
        TaskFlowRouter.flowId(for: card)
    }

    // MARK: - Computed Properties

    var hasMoreTasks: Bool { !taskQueue.isEmpty }
    var totalTaskCount: Int { taskQueue.count }
    var totalActiveTaskCount: Int { allActiveTasks.count }

    var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = userState?.name ?? ""
        let greeting: String
        switch hour {
        case 5..<12: greeting = "Good morning"
        case 12..<17: greeting = "Good afternoon"
        case 17..<22: greeting = "Good evening"
        default: greeting = "Hey"
        }
        return name.isEmpty ? "\(greeting)." : "\(greeting), \(name)."
    }

    var firstTimeWelcomeText: String {
        let daily = dailyTarget
        let paceDescription: String
        if daily == 0 {
            paceDescription = "We'll figure out your daily pace once tasks are generated."
        } else {
            let taskWord = daily == 1 ? "task" : "tasks"
            paceDescription = "Based on your move date, knocking out about \(daily) \(taskWord) per day will keep you right on track."
        }
        return "\(paceDescription)\n\nEach day, we'll serve up the tasks that matter most — just work through them and you're golden.\n\nIf you're feeling motivated and want to get ahead, go for it.\n\nIn the menu (top left), you'll find your full task list and move details. Feel free to update anything as plans change.\n\nAnd if you ever have a question about anything, just swipe up and ask!"
    }

    var firstTimeWelcomeGreeting: String {
        let name = userState?.name ?? ""
        return name.isEmpty ? "Welcome!" : "Welcome, \(name)!"
    }

    var dailyGreetingSubtitle: String {
        if dailyTarget == 0 { return "You're all caught up for today!" }
        let taskWord = dailyTarget == 1 ? "task" : "tasks"
        return "Just \(dailyTarget) \(taskWord) to knock out today!"
    }

    var returningMidDaySubtitle: String {
        let completed = dailyDoseCompletedCount
        let remaining = max(dailyTarget - completed, 0)
        if dailyTarget == 0 { return "You're all caught up for today!" }
        if remaining == 0 { return "You've knocked out all \(dailyTarget) for today!" }
        let taskWord = remaining == 1 ? "task" : "tasks"
        return "You've done \(completed) of \(dailyTarget) today — \(remaining) \(taskWord) to go."
    }

    var returningGreeting: String {
        let name = userState?.name ?? ""
        return name.isEmpty ? "Welcome back!" : "Welcome back, \(name)!"
    }

    // MARK: - Daily Dose Computed (math lives in DailyDoseEngine — Spec 03 Phase C)

    private let doseEngine = DailyDoseEngine()
    private let actionService = TaskActionService()

    private var daysUntilMoveValue: Int { userState?.daysUntilMove ?? 30 }
    private var bufferDays: Int { doseEngine.bufferDays(daysUntilMove: daysUntilMoveValue) }

    /// Today's frozen dose ids (Spec 04 Phase E). Set by loadTasks; nil only
    /// before the first load. While set, the announced target is the frozen
    /// count — mid-day inserts and completions can no longer move it.
    var frozenDoseTaskIds: [String]?

    var dailyTarget: Int {
        frozenDoseTaskIds?.count
            ?? doseEngine.dailyTarget(activeTaskCount: allActiveTasks.count, daysUntilMove: daysUntilMoveValue)
    }

    var isTodayComplete: Bool {
        dailyDoseCompletedCount >= dailyTarget && dailyTarget > 0
    }

    var dayNumber: Int {
        let firstLaunchStr = UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) ?? todayISOString()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let firstDate = formatter.date(from: firstLaunchStr) else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
        return days + 1
    }

    var totalPlanDays: Int { dayNumber + daysUntilMoveValue }

    var progressText: String {
        if dailyTarget == 0 { return "No tasks scheduled today" }
        let done = min(dailyDoseCompletedCount, dailyTarget)
        return "Today: \(done) of \(dailyTarget) done"
    }

    /// Today's completed-dose count for the Home counter (Spec 03 Phase D).
    var doseCompletedToday: Int { dailyDoseCompletedCount }

    /// Done-for-today closing line. Copy LOCKED (Spec 03 Phase D):
    /// "That's today. You're on pace for [move date]."
    var onPaceText: String {
        guard let moveDate = userState?.moveDate else { return "You're on pace." }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return "You're on pace for \(formatter.string(from: moveDate))."
    }

    var allCompleteSubtext: String {
        if let days = userState?.daysUntilMove {
            let unit = days == 1 ? "day" : "days"
            return "Your move is in \(days) \(unit), and your current task list is complete."
        }
        return "Your current task list is complete."
    }

    // MARK: - Load Tasks

    /// Pure task-surface split used before any Daily Dose or queue accounting.
    /// Contract presence always wins over legacy status/snooze interpretation.
    nonisolated static func projectHomeTasks(
        _ tasks: [PeezyCard],
        now: Date
    ) -> PeezyHomeTaskProjection {
        var actionable: [PeezyCard] = []
        var userInProgress: [PeezyCard] = []
        var contracted: [PeezyCard] = []

        for original in tasks {
            var card = original
            if card.dispositionContract != nil {
                contracted.append(card)
                continue
            }
            if card.status == .completed || card.status == .skipped { continue }
            if let snoozedUntil = card.snoozedUntil, snoozedUntil > now { continue }
            if card.status == .inProgress || card.status == .pending || card.status == .matchingInProgress {
                continue
            }
            if card.status == .userInProgress {
                if let returnDate = card.userInProgressReturnDate, returnDate <= now {
                    card.status = .upcoming
                    card.userInProgressDate = nil
                    card.userInProgressReturnDate = nil
                    actionable.append(card)
                } else {
                    userInProgress.append(card)
                }
            } else if card.shouldShow {
                actionable.append(card)
            }
        }

        contracted.sort {
            if $0.dueDate != $1.dueDate {
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }
        return PeezyHomeTaskProjection(
            actionableLegacy: actionable,
            userInProgressLegacy: userInProgress,
            readOnlyContractStatus: contracted
        )
    }

    func loadTasks() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run { self.state = .dailyGreeting }
            return
        }

        await MainActor.run { self.state = .loading }
        resetDailyCountIfNeeded()

        // Movers chain (plan v7 A5): denormalized-title migration for existing
        // BOOK_MOVERS docs. Cosmetic and nonblocking — never gates task load.
        Task { await actionService.migrateBookMoversPresentationIfNeeded(userId: userId) }

        do {
            if let moveDate = userState?.moveDate {
                do {
                    try await actionService.syncPackingPlanForLoad(
                        userId: userId,
                        moveDate: moveDate
                    )
                } catch {
                    // Packing-plan reconciliation must not block the rest of
                    // the user's daily work from loading.
                    print("⚠️ Packing-plan sync failed: \(error.localizedDescription)")
                }
            }

            let db = Firestore.firestore()
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .whereField("status", in: ["Upcoming", "pending", "matching_in_progress", "Snoozed", "InProgress", "UserInProgress"])
                .getDocuments()

            var decoded: [PeezyCard] = []
            let now = Date()

            for document in snapshot.documents {
                // Single decode path: PeezyCardFirestoreMapper (LE-025/031 successor).
                // Do not re-inline field decoding here.
                guard let card = PeezyCardFirestoreMapper.card(from: document) else { continue }
                decoded.append(card)
            }

            let projection = Self.projectHomeTasks(decoded, now: now)
            let sorted = doseEngine.urgencySorted(projection.actionableLegacy)

            // Dose freeze (Spec 04 Phase E): first computation of the day
            // locks {date, taskIds} on the user doc; every later load today
            // serves the frozen set. Tasks generated mid-day join tomorrow.
            let today = todayISOString()
            var frozen = await doseEngine.loadFrozenDose(userId: userId)
            if frozen?.date != today {
                let dose = DailyDoseEngine.FrozenDose(
                    date: today,
                    taskIds: doseEngine.taskIdsForNewDose(
                        from: sorted,
                        daysUntilMove: userState?.daysUntilMove ?? 30,
                        moveDate: userState?.moveDate
                    )
                )
                await doseEngine.freeze(dose, userId: userId)
                frozen = dose
            }
            let frozenIds = frozen?.taskIds ?? []

            await MainActor.run {
                self.allActiveTasks = sorted
                self.readOnlyContractStatus = projection.readOnlyContractStatus
                self.inProgressTaskCount = 0
                self.userInProgressTaskCount = projection.userInProgressLegacy.count
                self.frozenDoseTaskIds = frozenIds
                // Queue = frozen ids still active, in frozen order.
                self.taskQueue = frozenIds.compactMap { id in sorted.first { $0.id == id } }
                self.determineHomeState()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.state = .dailyGreeting
            }
        }
    }

    // MARK: - Start Next Task

    func startNextTask() {
        guard !taskQueue.isEmpty else {
            if allActiveTasks.isEmpty { state = .allComplete }
            else { state = .dailyComplete }
            return
        }

        guard let task = taskQueue.first, task.dispositionContract == nil else { return }
        taskQueue.removeFirst()
        currentTask = task

        // Nudges render inline on Home — no flow cover (Spec 09 Phase 3).
        if task.tier == "nudge" {
            state = .activeTask
            return
        }

        taskFlowWorkflowId = flowId(for: task)
        showTaskFlow = true
        state = .activeTask
    }

    // MARK: - Nudge Card Actions (Spec 09 Phase 3)

    /// The card advances only after its terminal claim commits. Retry retains
    /// the captured identity, operation id, choice, and conversion token.
    func answerNudge(yes: Bool) {
        guard nudgeAnswerState == .idle,
              nudgeOperation == nil,
              let task = currentTask,
              task.tier == "nudge" else { return }

        let choice: NudgeChoice = yes ? .converted : .dismissed
        let operationUid = uidProvider()
        let operation = NudgeOperation(
            task: task,
            choice: choice,
            userId: operationUid,
            opId: UUID().uuidString,
            token: "\(task.id)-convert"
        )
        nudgeOperation = operation
        nudgeAnswerError = nil
        error = nil
        nudgeAnswerState = .inFlight(choice)
        Task { await performNudgeOperation() }
    }

    func retryNudgeAnswer() {
        guard case .failed(let failedChoice, _) = nudgeAnswerState,
              let operation = nudgeOperation,
              operation.choice == failedChoice else { return }

        nudgeAnswerError = nil
        error = nil
        nudgeAnswerState = .inFlight(operation.choice)
        Task { await performNudgeOperation() }
    }

    private func performNudgeOperation() async {
        guard let operation = nudgeOperation else { return }
        var failurePhase: NudgeAnswerPhase = operation.choice == .converted ? .preSpawn : .claim

        do {
            guard let operationUid = operation.userId, !operationUid.isEmpty else {
                throw NudgeAnswerOperationError.missingAuthentication
            }
            guard !operation.task.id.isEmpty else {
                throw NudgeAnswerOperationError.missingTaskID
            }

            if operation.choice == .converted {
                guard let spawnId = operation.task.nudgeSpawnsId, !spawnId.isEmpty else {
                    throw NudgeAnswerOperationError.missingSpawnID
                }
                _ = try await bounded(to: spawnTimeout) {
                    try await self.spawnClient.spawn(
                        token: operation.token,
                        source: SpawnService.Source(
                            kind: "nudge",
                            id: operation.task.taskId ?? operation.task.id
                        ),
                        spawns: [SpawnService.Spawn(taskId: spawnId)],
                        answers: nil,
                        expectedUserId: operationUid
                    )
                }
                failurePhase = .postSpawn
            }

            let claimResult = try await bounded(to: claimTimeout) {
                try await TaskActionService().claimNudgeTerminal(
                    userId: operationUid,
                    taskId: operation.task.id,
                    choice: operation.choice,
                    opId: operation.opId,
                    runner: self.transactionRunner
                )
            }
            applyNudgeClaimResult(claimResult, operation: operation, userId: operationUid)
        } catch {
            failNudgeOperation(operation, phase: failurePhase, error: error)
        }
    }

    private func bounded<Value>(
        to timeout: Duration,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let resolver = NudgeTimeoutResolver(continuation: continuation)
            let operationTask = Task {
                do {
                    resolver.resolve(.success(try await operation()))
                } catch {
                    resolver.resolve(.failure(error))
                }
            }
            let timeoutTask = Task {
                do {
                    try await nudgeClock.sleep(for: timeout)
                    resolver.resolve(.failure(NudgeAnswerOperationError.timedOut))
                } catch {
                    resolver.resolve(.failure(error))
                }
            }
            resolver.install(operationTask: operationTask, timeoutTask: timeoutTask)
        }
    }

    private func applyNudgeClaimResult(
        _ result: ClaimResult,
        operation: NudgeOperation,
        userId: String
    ) {
        guard nudgeOperation?.opId == operation.opId else { return }

        let shouldCredit: Bool
        switch result {
        case .won:
            shouldCredit = operation.choice == .converted
        case .alreadyTerminal(let storedChoice, let storedOpId):
            shouldCredit = operation.choice == .converted
                && storedChoice == NudgeChoice.converted.rawValue
                && storedOpId == operation.opId
        }

        if shouldCredit {
            creditNudgeOperationIfNeeded(opId: operation.opId, userId: userId)
        }
        finishNudgeOperation(operation, accountingUserId: userId)
    }

    private func creditNudgeOperationIfNeeded(opId: String, userId: String) {
        guard var operation = nudgeOperation,
              operation.opId == opId,
              !operation.hasCredited else { return }

        operation.hasCredited = true
        nudgeOperation = operation
        PeezyHaptics.taskComplete()
        completedThisSession += 1
        recordDoseProgress(completedTask: true, userId: userId)
    }

    private func finishNudgeOperation(_ operation: NudgeOperation, accountingUserId: String) {
        allActiveTasks.removeAll { $0.id == operation.task.id }
        currentTask = nil
        isFocusedTask = false
        nudgeAnswerState = .idle
        nudgeAnswerError = nil
        error = nil
        nudgeOperation = nil
        advanceAfterTask(accountingUserId: accountingUserId)
    }

    private func failNudgeOperation(
        _ operation: NudgeOperation,
        phase: NudgeAnswerPhase,
        error: Error
    ) {
        guard nudgeOperation?.opId == operation.opId else { return }
        let message = error.localizedDescription
        nudgeAnswerError = message
        self.error = message
        nudgeAnswerState = .failed(operation.choice, phase)
    }

    // MARK: - Advance After Task

    private func advanceAfterTask(accountingUserId: String? = nil) {
        let completedCount = accountingUserId.map { dailyDoseCompletedCount(for: $0) }
            ?? dailyDoseCompletedCount
        if allActiveTasks.isEmpty {
            currentTask = nil
            isFocusedTask = false
            state = .allComplete
        } else if completedCount >= dailyTarget {
            currentTask = nil
            isFocusedTask = false
            state = .dailyComplete
        } else if !taskQueue.isEmpty {
            startNextTask()
        } else {
            determineHomeState(accountingUserId: accountingUserId)
        }
    }

    private func finishFlowAndDeferAdvance() {
        currentTask = nil
        isFocusedTask = false
        pendingAdvance = true
        showTaskFlow = false
    }

    private func recordDoseProgress(completedTask: Bool) {
        recordDoseProgress(completedTask: completedTask, userId: userId)
    }

    private func recordDoseProgress(completedTask: Bool, userId: String) {
        let previousDoseCount = dailyDoseCompletedCount(for: userId)
        let previousTotalCount = totalCompletedCount(for: userId)
        let wasFirstCompletion = previousTotalCount == 0
        let wasDayComplete = isTodayComplete(completedCount: previousDoseCount)
        let updatedDoseCount = previousDoseCount + 1

        setDailyDoseCompletedCount(updatedDoseCount, for: userId)
        if completedTask {
            setTotalCompletedCount(previousTotalCount + 1, for: userId)
            if wasFirstCompletion {
                AnalyticsEvents.firstDoseCompleted()
            }
        }
        if !wasDayComplete && isTodayComplete(completedCount: updatedDoseCount) {
            AnalyticsEvents.dayDoseCompleted(dayNumber: dayNumber(for: userId))
        }
    }

    // MARK: - Complete Simple Task

    func completeCurrentTask() {
        guard let task = currentTask else { return }
        Task { await actionService.markTaskCompleted(task) }
        PeezyHaptics.taskComplete()
        completedThisSession += 1
        recordDoseProgress(completedTask: true)
        allActiveTasks.removeAll { $0.id == task.id }
        currentTask = nil
        isFocusedTask = false
        advanceAfterTask()
    }

    // MARK: - Mark Task User In Progress

    func markCurrentTaskUserInProgress() {
        guard let task = currentTask else { return }
        let returnDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        Task { await actionService.writeUserInProgress(task, returnDate: returnDate) }
        recordDoseProgress(completedTask: false)
        completedThisSession += 1
        currentTask = nil
        isFocusedTask = false
        advanceAfterTask()
    }

    // MARK: - Focus Task (from Task List)

    func focusTask(_ task: PeezyCard) {
        guard task.dispositionContract == nil else { return }
        taskQueue.removeAll { $0.id == task.id }
        currentTask = task
        isFocusedTask = true

        taskFlowWorkflowId = flowId(for: task)
        showTaskFlow = true
        state = .activeTask
    }

    // MARK: - Complete Task Flow

    func completeTaskFlow() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }

        Task { await actionService.markTaskCompleted(task) }

        PeezyHaptics.taskComplete()
        completedThisSession += 1
        recordDoseProgress(completedTask: true)
        allActiveTasks.removeAll { $0.id == task.id }

        finishFlowAndDeferAdvance()
    }

    func dismissTaskFlow() {
        if let task = currentTask {
            taskQueue.insert(task, at: 0)
        }
        currentTask = nil
        isFocusedTask = false
        pendingAdvance = false
        showTaskFlow = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.determineHomeState()
        }
    }

    // MARK: - Status Card Actions

    func statusActionDone() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }

        Task { await actionService.markTaskCompleted(task) }

        PeezyHaptics.taskComplete()
        completedThisSession += 1
        recordDoseProgress(completedTask: true)
        allActiveTasks.removeAll { $0.id == task.id }

        finishFlowAndDeferAdvance()
    }

    func statusActionInProgress() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }

        let returnDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        Task { await actionService.writeUserInProgress(task, returnDate: returnDate) }

        recordDoseProgress(completedTask: false)
        completedThisSession += 1

        finishFlowAndDeferAdvance()
    }

    func statusActionLater() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }

        let snoozedUntil = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
        Task { await actionService.writeSnooze(task, snoozedUntil: snoozedUntil) }

        allActiveTasks.removeAll { $0.id == task.id }
        recordDoseProgress(completedTask: false)

        finishFlowAndDeferAdvance()
    }

    /// The custom flow has already written the permanent Tasks-tab state.
    func statusActionDismissedPermanently() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }
        allActiveTasks.removeAll { $0.id == task.id }
        recordDoseProgress(completedTask: false)
        completedThisSession += 1
        finishFlowAndDeferAdvance()
    }

    /// Legacy callback retained for callers that still use the old action
    /// name. A submitted flow is complete once its action sheet is ready.
    func statusActionSubmittedToPeezy() {
        statusActionDone()
    }

    // MARK: - Already-persisted terminals (movers chain, plan v7)

    /// The flow already performed its own awaited, throwing completion write
    /// (which owns completedAt). This path does ONLY local accounting — a
    /// second write here would move the completion timestamp to whenever the
    /// user tapped Done on the confirmation screen.
    func completeTaskFlowAlreadyPersisted() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }

        PeezyHaptics.taskComplete()
        completedThisSession += 1
        recordDoseProgress(completedTask: true)
        allActiveTasks.removeAll { $0.id == task.id }

        finishFlowAndDeferAdvance()
    }

    /// The flow already performed its own awaited, throwing two-day snooze
    /// write. Local accounting only — mirrors statusActionLater minus the
    /// detached writeSnooze.
    func statusActionLaterAlreadyPersisted() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }

        allActiveTasks.removeAll { $0.id == task.id }
        recordDoseProgress(completedTask: false)

        finishFlowAndDeferAdvance()
    }

    // MARK: - Get Ahead

    func getAhead() {
        gettingAhead = true
        let queueIds = Set(taskQueue.map { $0.id })
        let nextTask = allActiveTasks
            .sorted { ($0.urgencyPercentage ?? 0) > ($1.urgencyPercentage ?? 0) }
            .first { !queueIds.contains($0.id) }

        if let task = nextTask {
            taskQueue = [task]
            startNextTask()
        } else {
            state = .allComplete
        }
    }

    // MARK: - State Determination

    func determineHomeState(accountingUserId: String? = nil) {
        if isFocusedTask { return }

        let resolvedUserId = accountingUserId ?? userId

        if !UserDefaults.standard.bool(forKey: hasSeenFirstTimeWelcomeKey(for: resolvedUserId)) {
            state = .firstTimeWelcome
            return
        }

        if allActiveTasks.isEmpty {
            state = .allComplete
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        let greetingKey = lastGreetingDateKey(for: resolvedUserId)
        let lastGreeting = UserDefaults.standard.object(forKey: greetingKey) as? Date
        let isNewDay = lastGreeting == nil || !Calendar.current.isDate(lastGreeting!, inSameDayAs: today)

        if isNewDay {
            state = .dailyGreeting
            UserDefaults.standard.set(today, forKey: greetingKey)
            return
        }

        let completedToday = dailyDoseCompletedCount(for: resolvedUserId)
        if completedToday > 0 && completedToday < dailyTarget {
            state = .returningMidDay
            return
        }

        if isTodayComplete(completedCount: completedToday) {
            state = .dailyComplete
            return
        }

        state = .dailyGreeting
    }

    func dismissFirstTimeWelcome() {
        UserDefaults.standard.set(true, forKey: kHasSeenFirstTimeWelcome)
        if taskQueue.isEmpty {
            if let frozenIds = frozenDoseTaskIds {
                // Rebuild strictly from today's frozen set (Spec 04 Phase E).
                taskQueue = frozenIds.compactMap { id in allActiveTasks.first { $0.id == id } }
            } else {
                taskQueue = Array(allActiveTasks.prefix(dailyTarget))
            }
        }
        determineHomeState()
    }

    // MARK: - Daily Dose UserDefaults

    private var dailyDoseCompletedCount: Int {
        get { UserDefaults.standard.integer(forKey: kDailyDoseCompletedCount) }
        set { UserDefaults.standard.set(newValue, forKey: kDailyDoseCompletedCount) }
    }

    private func dailyDoseCompletedCount(for userId: String) -> Int {
        UserDefaults.standard.integer(forKey: dailyDoseCompletedKey(for: userId))
    }

    private func setDailyDoseCompletedCount(_ count: Int, for userId: String) {
        UserDefaults.standard.set(count, forKey: dailyDoseCompletedKey(for: userId))
    }

    private func totalCompletedCount(for userId: String) -> Int {
        UserDefaults.standard.integer(forKey: totalCompletedKey(for: userId))
    }

    private func setTotalCompletedCount(_ count: Int, for userId: String) {
        UserDefaults.standard.set(count, forKey: totalCompletedKey(for: userId))
    }

    private func isTodayComplete(completedCount: Int) -> Bool {
        completedCount >= dailyTarget && dailyTarget > 0
    }

    private func dayNumber(for userId: String) -> Int {
        let firstLaunchStr = UserDefaults.standard.string(
            forKey: dailyDoseFirstLaunchDateKey(for: userId)
        ) ?? todayISOString()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let firstDate = formatter.date(from: firstLaunchStr) else { return 1 }
        let days = Calendar.current.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
        return days + 1
    }

    private func dailyDoseCompletedKey(for userId: String) -> String {
        "peezy.\(userId).dailyDose.completedCount"
    }

    private func dailyDoseLastDateKey(for userId: String) -> String {
        "peezy.\(userId).dailyDose.lastDate"
    }

    private func dailyDoseFirstLaunchDateKey(for userId: String) -> String {
        "peezy.\(userId).dailyDose.firstLaunchDate"
    }

    private func hasSeenFirstTimeWelcomeKey(for userId: String) -> String {
        "peezy.\(userId).hasSeenFirstTimeWelcome"
    }

    private func lastGreetingDateKey(for userId: String) -> String {
        "peezy.\(userId).lastGreetingDate"
    }

    private func totalCompletedKey(for userId: String) -> String {
        "peezy.\(userId).totalCompletedCount"
    }

    private func todayISOString() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: Date())
    }

    private func resetDailyCountIfNeeded() {
        let today = todayISOString()
        let lastDate = UserDefaults.standard.string(forKey: kDailyDoseLastDate) ?? ""
        if today != lastDate {
            dailyDoseCompletedCount = 0
            UserDefaults.standard.set(today, forKey: kDailyDoseLastDate)
        }
        if UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) == nil {
            UserDefaults.standard.set(today, forKey: kDailyDoseFirstLaunchDate)
        }
    }

    func resetDailyCountIfNeededPublic() {
        resetDailyCountIfNeeded()
    }

    // MARK: - Previews

    #if DEBUG
    static func preview(state: HomeState, tasks: [PeezyCard]? = nil) -> PeezyHomeViewModel {
        let vm = PeezyHomeViewModel()
        vm.userState = UserState(userId: "preview", name: "Adam")
        vm.state = state
        if let tasks = tasks {
            vm.allActiveTasks = tasks
            vm.taskQueue = tasks
        } else {
            let sampleTasks = [
                PeezyCard(type: .task, title: "Forward mail", subtitle: "Set up USPS forwarding", colorName: "blue"),
                PeezyCard(type: .task, title: "Update license", subtitle: "New state driver's license", colorName: "green"),
                PeezyCard(type: .task, title: "Find movers", subtitle: "Get quotes from 3 companies", colorName: "orange"),
            ]
            vm.allActiveTasks = sampleTasks
            vm.taskQueue = sampleTasks
        }
        return vm
    }
    #endif

}
