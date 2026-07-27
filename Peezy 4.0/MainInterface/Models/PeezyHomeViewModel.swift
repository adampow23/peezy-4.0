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
import FirebaseFunctions

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

    // MARK: - Daily Dose State

    var allActiveTasks: [PeezyCard] = []
    var inProgressTaskCount: Int = 0
    var userInProgressTaskCount: Int = 0
    var gettingAhead: Bool = false
    var isFocusedTask: Bool = false
    var currentBatchOffset: Int = 0

    // MARK: - User Context

    var userState: UserState?

    // MARK: - UserDefaults Keys

    private var userId: String { Auth.auth().currentUser?.uid ?? "anon" }
    private var kDailyDoseCompletedCount: String { "peezy.\(userId).dailyDose.completedCount" }
    private var kDailyDoseLastDate: String { "peezy.\(userId).dailyDose.lastDate" }
    private var kDailyDoseFirstLaunchDate: String { "peezy.\(userId).dailyDose.firstLaunchDate" }
    private var kHasSeenFirstTimeWelcome: String { "peezy.\(userId).hasSeenFirstTimeWelcome" }
    private var kLastGreetingDate: String { "peezy.\(userId).lastGreetingDate" }
    private var kTotalCompletedCount: String { "peezy.\(userId).totalCompletedCount" }

    var totalCompletedCount: Int {
        get { UserDefaults.standard.integer(forKey: kTotalCompletedCount) }
        set { UserDefaults.standard.set(newValue, forKey: kTotalCompletedCount) }
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

    /// Data-driven routing (Spec 04 Phase C — the newFlowIds allowlist is
    /// gone): every card resolves to a flow id — workflowId when present,
    /// else the lowercased taskId (the off-app convention). The router
    /// resolves it against the explicit map or flowDefinitions; unknown ids
    /// render the coming-right-up card, never a dead end.
    private func flowId(for card: PeezyCard) -> String {
        card.workflowId ?? (card.taskId ?? card.id).lowercased()
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
            var text = "Your move is in \(days) \(unit) and everything is on track."
            if inProgressTaskCount > 0 {
                let itemUnit = inProgressTaskCount == 1 ? "item" : "items"
                text += "\n\nPeezy is still working on \(inProgressTaskCount) \(itemUnit) — we'll keep you posted."
            }
            return text
        }
        if inProgressTaskCount > 0 {
            let itemUnit = inProgressTaskCount == 1 ? "item" : "items"
            return "Peezy is still working on \(inProgressTaskCount) \(itemUnit) — we'll keep you posted."
        }
        return "Peezy is handling the rest."
    }

    // MARK: - Load Tasks

    func loadTasks() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run { self.state = .dailyGreeting }
            return
        }

        await MainActor.run { self.state = .loading }
        resetDailyCountIfNeeded()

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

            var cards: [PeezyCard] = []
            var inProgressBuffer: [PeezyCard] = []
            var userInProgressBuffer: [PeezyCard] = []
            let now = Date()

            for document in snapshot.documents {
                // Single decode path: PeezyCardFirestoreMapper (LE-025/031 successor).
                // Do not re-inline field decoding here.
                guard var card = PeezyCardFirestoreMapper.card(from: document) else { continue }
                if card.status == .completed || card.status == .skipped { continue }

                if let snoozedUntil = card.snoozedUntil, snoozedUntil > now { continue }

                if card.status == .inProgress || card.status == .pending || card.status == .matchingInProgress {
                    // pending / matching_in_progress = server working — waiting, not actionable
                    inProgressBuffer.append(card)
                } else if card.status == .userInProgress {
                    if let returnDate = card.userInProgressReturnDate, returnDate <= now {
                        card.status = .upcoming
                        card.userInProgressDate = nil
                        card.userInProgressReturnDate = nil
                        cards.append(card)
                    } else {
                        userInProgressBuffer.append(card)
                    }
                } else if card.shouldShow {
                    cards.append(card)
                }
            }

            let sorted = doseEngine.urgencySorted(cards)

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
                        daysUntilMove: userState?.daysUntilMove ?? 30
                    )
                )
                await doseEngine.freeze(dose, userId: userId)
                frozen = dose
            }
            let frozenIds = frozen?.taskIds ?? []

            await MainActor.run {
                self.allActiveTasks = sorted
                self.inProgressTaskCount = inProgressBuffer.count
                self.userInProgressTaskCount = userInProgressBuffer.count
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

        let task = taskQueue.removeFirst()
        currentTask = task

        taskFlowWorkflowId = flowId(for: task)
        showTaskFlow = true
        state = .activeTask
    }

    // MARK: - Advance After Task

    private func advanceAfterTask() {
        if allActiveTasks.isEmpty {
            currentTask = nil
            isFocusedTask = false
            state = .allComplete
        } else if dailyDoseCompletedCount >= dailyTarget {
            currentTask = nil
            isFocusedTask = false
            state = .dailyComplete
        } else if !taskQueue.isEmpty {
            startNextTask()
        } else {
            determineHomeState()
        }
    }

    private func finishFlowAndDeferAdvance() {
        currentTask = nil
        isFocusedTask = false
        pendingAdvance = true
        showTaskFlow = false
    }

    // MARK: - Complete Simple Task

    func completeCurrentTask() {
        guard let task = currentTask else { return }
        Task { await actionService.markTaskCompleted(task) }
        PeezyHaptics.taskComplete()
        completedThisSession += 1
        dailyDoseCompletedCount += 1
        totalCompletedCount += 1
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
        dailyDoseCompletedCount += 1
        completedThisSession += 1
        currentTask = nil
        isFocusedTask = false
        advanceAfterTask()
    }

    // MARK: - Mark Task Peezy Handling

    func markCurrentTaskPeezyHandling() {
        guard let task = currentTask else { return }
        Task {
            await actionService.markTaskInProgress(task)
            Task {
                do {
                    let callable = Functions.functions().httpsCallable("requestConcierge")
                    let moveDateStr: String
                    if let date = userState?.moveDate { moveDateStr = ISO8601DateFormatter().string(from: date) }
                    else { moveDateStr = "" }
                    let currentAddr = userState?.currentFullAddress ?? ""
                    let newAddr = userState?.newFullAddress ?? ""
                    let payload: [String: Any] = [
                        "taskId": task.taskId ?? task.id, "taskTitle": task.title,
                        "taskCategory": task.taskCategory ?? "", "userId": userState?.userId ?? "",
                        "userName": userState?.name ?? "", "currentAddress": currentAddr,
                        "newAddress": newAddr, "moveDate": moveDateStr,
                        "moveDistance": userState?.moveDistance?.rawValue ?? ""
                    ]
                    _ = try await callable.call(payload)
                } catch {
                    print("Concierge notification failed: \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                allActiveTasks.removeAll { $0.id == task.id }
                dailyDoseCompletedCount += 1
                completedThisSession += 1
                totalCompletedCount += 1
                currentTask = nil
                isFocusedTask = false
                advanceAfterTask()
            }
        }
    }

    // MARK: - Focus Task (from Task List)

    func focusTask(_ task: PeezyCard) {
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

        let isSelfService = task.selfServiceOnly || task.actionType == "off-app"
        Task {
            if isSelfService { await actionService.markTaskCompleted(task) }
            else { await actionService.markTaskInProgress(task) }
        }

        PeezyHaptics.taskComplete()
        completedThisSession += 1
        dailyDoseCompletedCount += 1
        totalCompletedCount += 1
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
        dailyDoseCompletedCount += 1
        totalCompletedCount += 1
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

        dailyDoseCompletedCount += 1
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
        dailyDoseCompletedCount += 1

        finishFlowAndDeferAdvance()
    }

    /// The custom flow has already written the permanent Tasks-tab state.
    func statusActionDismissedPermanently() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }
        allActiveTasks.removeAll { $0.id == task.id }
        dailyDoseCompletedCount += 1
        completedThisSession += 1
        finishFlowAndDeferAdvance()
    }

    /// The callable has already moved the task into Peezy's in-progress lane.
    func statusActionSubmittedToPeezy() {
        guard let task = currentTask else {
            showTaskFlow = false
            return
        }
        allActiveTasks.removeAll { $0.id == task.id }
        inProgressTaskCount += 1
        dailyDoseCompletedCount += 1
        completedThisSession += 1
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

    func determineHomeState() {
        if isFocusedTask { return }

        if !UserDefaults.standard.bool(forKey: kHasSeenFirstTimeWelcome) {
            state = .firstTimeWelcome
            return
        }

        if allActiveTasks.isEmpty {
            state = .allComplete
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        let lastGreeting = UserDefaults.standard.object(forKey: kLastGreetingDate) as? Date
        let isNewDay = lastGreeting == nil || !Calendar.current.isDate(lastGreeting!, inSameDayAs: today)

        if isNewDay {
            state = .dailyGreeting
            UserDefaults.standard.set(today, forKey: kLastGreetingDate)
            return
        }

        let completedToday = dailyDoseCompletedCount
        if completedToday > 0 && completedToday < dailyTarget {
            state = .returningMidDay
            return
        }

        if isTodayComplete {
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
