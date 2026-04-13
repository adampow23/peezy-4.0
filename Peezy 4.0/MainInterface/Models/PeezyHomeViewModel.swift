//
//  PeezyHomeViewModel.swift
//  Peezy
//
//  State machine view model for the main home screen.
//
//  States: loading → welcome → task → done
//
//  Dependencies:
//  - WorkflowService (for Firebase submission via per-task flows)
//  - PeezyCard (existing, unchanged)
//  - UserState (existing, unchanged)
//  - FirebaseFirestore, FirebaseAuth
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
        case firstTimeWelcome    // One-time only, after first assessment
        case dailyGreeting       // Start of each new day
        case returningMidDay     // Came back after already starting today
        case activeTask          // Showing a task card
        case dailyComplete       // Today's batch done
        case allComplete         // Every task done or in progress
    }

    var state: HomeState = .loading
    var error: String?

    // MARK: - Task Queue

    /// All available tasks sorted by urgency (earliest due / highest priority first)
    var taskQueue: [PeezyCard] = []

    /// The task currently being worked on
    var currentTask: PeezyCard?

    /// How many tasks completed in this session (for done screen messaging)
    var completedThisSession: Int = 0

    // MARK: - Daily Dose State

    /// All active tasks (not InProgress) sorted by urgency — full list, not sliced
    var allActiveTasks: [PeezyCard] = []

    /// Count of InProgress tasks (Peezy is on it) for the "all done" screen
    var inProgressTaskCount: Int = 0

    /// Count of UserInProgress tasks (user is working on it)
    var userInProgressTaskCount: Int = 0

    /// Whether the user has opted to get ahead of schedule
    var gettingAhead: Bool = false

    /// Set to true when user navigated here from the task list — prevents determineHomeState() from overriding
    var isFocusedTask: Bool = false

    /// Which batch offset we're on: 0 = today, 1 = +1 day ahead, etc.
    var currentBatchOffset: Int = 0

    // MARK: - User Context

    var userState: UserState?

    // MARK: - UserDefaults Keys (per-user, scoped by UID)

    private var userId: String {
        Auth.auth().currentUser?.uid ?? "anon"
    }

    private var kDailyDoseCompletedCount: String {
        "peezy.\(userId).dailyDose.completedCount"
    }
    private var kDailyDoseLastDate: String {
        "peezy.\(userId).dailyDose.lastDate"
    }
    private var kDailyDoseFirstLaunchDate: String {
        "peezy.\(userId).dailyDose.firstLaunchDate"
    }
    private var kHasSeenFirstTimeWelcome: String {
        "peezy.\(userId).hasSeenFirstTimeWelcome"
    }
    private var kLastGreetingDate: String {
        "peezy.\(userId).lastGreetingDate"
    }
    private var kTotalCompletedCount: String {
        "peezy.\(userId).totalCompletedCount"
    }

    var totalCompletedCount: Int {
        get { UserDefaults.standard.integer(forKey: kTotalCompletedCount) }
        set { UserDefaults.standard.set(newValue, forKey: kTotalCompletedCount) }
    }

    // MARK: - Inventory Scanner

    var showInventoryScanner = false

    // MARK: - Task Flow System

    /// When set, the View presents the standalone task flow via fullScreenCover
    var showTaskFlow = false

    /// The workflowId (or taskId) of the flow to present
    var taskFlowWorkflowId: String?

    /// WorkflowIds that have standalone flow files.
    private static let newFlowIds: Set<String> = [
        // Type 1: Self-Service
        "return_key_fobs_remotes",
        "schedule_time_off_work",
        "update_employer_records",
        "update_drivers_license",
        "new_drivers_license",
        "register_vehicle",
        "photograph_rental_condition",
        "buy_packing_supplies",
        "buy_cleaning_supplies",
        "defrost_freezer",
        "diy_deep_cleaning",
        "diy_final_cleaning",
        "forward_mail_usps",
        "coa_schools",
        "transfer_daycare",
        "update_credit_card",
        "update_student_loans",
        "begin_school_transfer",
        "new_school_enrollment",
        "setup_daycare",
        // Type 2: Manage-Provider
        "manage_gym",
        "manage_doctor",
        "manage_dentist",
        "manage_vet",
        "transfer_pharmacy_records",
        "transfer_specialists_records",
        "manage_yoga",
        "manage_spin",
        "manage_massage",
        "manage_bank",
        "update_investment",
        // Type 3: Decision Only
        "arrange_parking_new",
        "arrange_parking_old",
        "reserve_elevators_new",
        "reserve_elevators_old",
        "setup_utilities",
        "cancel_utilities",
        "transfer_utilities",
        // Type 4: Insurance
        "handle_auto_insurance", "update_auto_insurance",
        "handle_home_insurance",
        "cancel_renters_insurance", "setup_renters_insurance", "transfer_renters_insurance",
        "cancel_condo_insurance", "setup_condo_insurance", "transfer_condo_insurance",
        "cancel_homeowners_insurance", "setup_homeowners_insurance", "transfer_homeowners_insurance",
        // Type 5: Survey + Submit
        "rent_truck",
        // Type 6: Complex-Vendor
        "book_movers",
        "book_cleaners",
        "setup_internet",
        "sell_items",
        "remove_items"
    ]

    /// Returns the flow ID for a card, or nil if no flow exists.
    private func newFlowId(for card: PeezyCard) -> String? {
        if let wid = card.workflowId, Self.newFlowIds.contains(wid) {
            return wid
        }
        if let tid = card.taskId {
            let lowered = tid.lowercased()
            if Self.newFlowIds.contains(lowered) {
                return lowered
            }
        }
        return nil
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

    // MARK: - First Time Welcome Text

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

    // MARK: - Daily Greeting Text

    var dailyGreetingSubtitle: String {
        if dailyTarget == 0 {
            return "You're all caught up for today!"
        }
        let taskWord = dailyTarget == 1 ? "task" : "tasks"
        return "Just \(dailyTarget) \(taskWord) to knock out today!"
    }

    // MARK: - Returning Mid-Day Text

    var returningMidDaySubtitle: String {
        let completed = dailyDoseCompletedCount
        let remaining = max(dailyTarget - completed, 0)
        if dailyTarget == 0 {
            return "You're all caught up for today!"
        }
        if remaining == 0 {
            return "You've knocked out all \(dailyTarget) for today!"
        }
        let taskWord = remaining == 1 ? "task" : "tasks"
        return "You've done \(completed) of \(dailyTarget) today — \(remaining) \(taskWord) to go."
    }

    var returningGreeting: String {
        let name = userState?.name ?? ""
        return name.isEmpty ? "Welcome back!" : "Welcome back, \(name)!"
    }

    // MARK: - Daily Dose Computed Properties

    private var daysUntilMoveValue: Int {
        userState?.daysUntilMove ?? 30
    }

    private var bufferDays: Int {
        if daysUntilMoveValue <= 10 { return 0 }
        if daysUntilMoveValue <= 14 { return 3 }
        return 7
    }

    private var workingDays: Int {
        max(daysUntilMoveValue - bufferDays, 1)
    }

    var dailyTarget: Int {
        guard !allActiveTasks.isEmpty else { return 0 }
        return max(Int(ceil(Double(allActiveTasks.count) / Double(workingDays))), 1)
    }

    var isTodayComplete: Bool {
        dailyDoseCompletedCount >= dailyTarget && dailyTarget > 0
    }

    var dayNumber: Int {
        let firstLaunchStr = UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) ?? todayISOString()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let firstDate = formatter.date(from: firstLaunchStr) else { return 1 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
        return days + 1
    }

    var totalPlanDays: Int {
        dayNumber + daysUntilMoveValue
    }

    var progressText: String {
        if dailyTarget == 0 {
            return "No tasks scheduled today"
        }
        let done = min(dailyDoseCompletedCount, dailyTarget)
        return "Today: \(done) of \(dailyTarget) done"
    }

    var celebrationSubtext: String {
        if gettingAhead {
            let extraCompleted = completedThisSession - dailyTarget
            if extraCompleted > 0 {
                let unit = extraCompleted == 1 ? "task" : "tasks"
                return "Still going! You're \(extraCompleted) \(unit) ahead of schedule."
            }
        }
        if daysUntilMoveValue <= bufferDays + 2 {
            return "You're in great shape for move day."
        }
        return "Right on schedule. Enjoy the rest of your day."
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

    // MARK: - Load Tasks from Firestore

    func loadTasks() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run { self.state = .dailyGreeting }
            return
        }

        await MainActor.run { self.state = .loading }
        resetDailyCountIfNeeded()

        do {
            let db = Firestore.firestore()

            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .whereField("status", in: ["Upcoming", "pending", "Snoozed", "InProgress", "UserInProgress"])
                .getDocuments()

            var cards: [PeezyCard] = []
            var inProgressBuffer: [PeezyCard] = []
            var userInProgressBuffer: [PeezyCard] = []
            let now = Date()

            for document in snapshot.documents {
                let data = document.data()

                let statusString = data["status"] as? String ?? "Upcoming"
                let status = TaskStatus(rawValue: statusString) ?? .upcoming

                if status == .completed || status == .skipped { continue }

                let priorityString = data["priority"] as? String ?? "Medium"
                let priority: PeezyCard.Priority
                switch priorityString.lowercased() {
                case "high", "urgent": priority = .high
                case "low": priority = .low
                default: priority = .normal
                }

                let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
                let snoozedUntil = (data["snoozedUntil"] as? Timestamp)?.dateValue()
                let lastSnoozedAt = (data["lastSnoozedAt"] as? Timestamp)?.dateValue()
                let urgencyPercentage = (data["urgencyPercentage"] as? NSNumber)?.intValue
                let userInProgressDate = (data["userInProgressDate"] as? Timestamp)?.dateValue()
                let userInProgressReturnDate = (data["userInProgressReturnDate"] as? Timestamp)?.dateValue()

                if let snoozedUntil = snoozedUntil, snoozedUntil > now { continue }

                let isVendorTask = (data["category"] as? String)?.lowercased().contains("vendor") ?? false
                let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task

                var card = PeezyCard(
                    id: document.documentID,
                    type: cardType,
                    title: data["title"] as? String ?? "Untitled Task",
                    subtitle: data["desc"] as? String ?? "",
                    colorName: colorNameForPriority(priority),
                    taskId: data["id"] as? String ?? document.documentID,
                    workflowId: data["workflowId"] as? String,
                    vendorCategory: isVendorTask ? (data["category"] as? String) : nil,
                    priority: priority,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    status: status,
                    dueDate: dueDate,
                    snoozedUntil: snoozedUntil,
                    lastSnoozedAt: lastSnoozedAt,
                    taskCategory: data["category"] as? String,
                    urgencyPercentage: urgencyPercentage,
                    userInProgressDate: userInProgressDate,
                    userInProgressReturnDate: userInProgressReturnDate,
                    selfServiceOnly: (data["selfServiceOnly"] as? Bool) ?? false,
                    actionType: data["actionType"] as? String,
                    taskType: data["taskType"] as? String,
                    tips: data["tips"] as? String,
                    whyNeeded: data["whyNeeded"] as? String,
                    estPeezy: data["estPeezy"] as? String,
                    estHours: (data["estHours"] as? NSNumber)?.doubleValue
                )

                if card.status == .inProgress {
                    inProgressBuffer.append(card)
                } else if card.status == .userInProgress {
                    if let returnDate = userInProgressReturnDate, returnDate <= now {
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

            let inProgressCards = inProgressBuffer
            let userInProgressCards = userInProgressBuffer
            let activeCards = cards

            let sorted = activeCards.sorted { a, b in
                let ua = a.urgencyPercentage ?? 0
                let ub = b.urgencyPercentage ?? 0
                if ua != ub { return ua > ub }
                return a.title < b.title
            }

            await MainActor.run {
                self.allActiveTasks = sorted
                self.inProgressTaskCount = inProgressCards.count
                self.userInProgressTaskCount = userInProgressCards.count
                let batch = Array(sorted.prefix(self.dailyTarget))
                self.taskQueue = batch
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
            if allActiveTasks.isEmpty {
                state = .allComplete
            } else {
                state = .dailyComplete
            }
            return
        }

        let task = taskQueue.removeFirst()
        currentTask = task

        if task.actionType == "in-app-inventory" {
            showInventoryScanner = true
            state = .activeTask
            return
        }

        if let flowId = newFlowId(for: task) {
            taskFlowWorkflowId = flowId
            showTaskFlow = true
            state = .activeTask
            return
        }

        // No flow found — shouldn't happen for shipped tasks
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

    // MARK: - Complete Simple Task

    func completeCurrentTask() {
        guard let task = currentTask else { return }

        Task {
            await markTaskCompleted(task)
        }

        completedThisSession += 1
        dailyDoseCompletedCount += 1
        totalCompletedCount += 1
        allActiveTasks.removeAll { $0.id == task.id }
        currentTask = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    // MARK: - Mark Task User In Progress ("I'm on it")

    func markCurrentTaskUserInProgress() {
        guard let task = currentTask else { return }

        let returnDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

        Task {
            await writeUserInProgress(task, returnDate: returnDate)
        }

        dailyDoseCompletedCount += 1
        completedThisSession += 1
        currentTask = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    // MARK: - Mark Task Peezy Handling ("Peezy, handle this")

    func markCurrentTaskPeezyHandling() {
        guard let task = currentTask else { return }
        Task {
            await markTaskInProgress(task)

            Task {
                do {
                    let callable = Functions.functions().httpsCallable("requestConcierge")
                    let moveDateStr: String
                    if let date = userState?.moveDate {
                        moveDateStr = ISO8601DateFormatter().string(from: date)
                    } else {
                        moveDateStr = ""
                    }
                    let currentAddr = [userState?.originCity, userState?.originState]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    let newAddr = [userState?.destinationCity, userState?.destinationState]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                    let payload: [String: Any] = [
                        "taskId": task.taskId ?? task.id,
                        "taskTitle": task.title,
                        "taskCategory": task.taskCategory ?? "",
                        "userId": userState?.userId ?? "",
                        "userName": userState?.name ?? "",
                        "currentAddress": currentAddr,
                        "newAddress": newAddr,
                        "moveDate": moveDateStr,
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

        if task.actionType == "in-app-inventory" {
            showInventoryScanner = true
            state = .activeTask
            return
        }

        if let flowId = newFlowId(for: task) {
            taskFlowWorkflowId = flowId
            showTaskFlow = true
            state = .activeTask
            return
        }

        state = .activeTask
    }

    // MARK: - Complete Task Flow

    /// Called when a task flow completes (user tapped Submit/Done on SummaryCard).
    func completeTaskFlow() {
        guard let task = currentTask else { return }

        let isSelfService = task.selfServiceOnly || task.actionType == "off-app"

        Task {
            if isSelfService {
                await markTaskCompleted(task)
            } else {
                await markTaskInProgress(task)
            }
        }

        completedThisSession += 1
        dailyDoseCompletedCount += 1
        totalCompletedCount += 1
        allActiveTasks.removeAll { $0.id == task.id }
        currentTask = nil
        showTaskFlow = false
        taskFlowWorkflowId = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    /// Called when user dismisses a task flow (DismissButton / swipe dismiss).
    func dismissTaskFlow() {
        if let task = currentTask {
            taskQueue.insert(task, at: 0)
        }
        currentTask = nil
        showTaskFlow = false
        taskFlowWorkflowId = nil
        isFocusedTask = false
        determineHomeState()
    }

    // MARK: - Status Card Actions (from Task Flows)

    /// StatusCard: "Already done" — marks task completed in Firestore, advances.
    func statusActionDone() {
        guard let task = currentTask else { return }

        Task {
            await markTaskCompleted(task)
        }

        completedThisSession += 1
        dailyDoseCompletedCount += 1
        totalCompletedCount += 1
        allActiveTasks.removeAll { $0.id == task.id }
        currentTask = nil
        showTaskFlow = false
        taskFlowWorkflowId = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    /// StatusCard: "Mark as in progress" — marks UserInProgress, returns in 3 days.
    func statusActionInProgress() {
        guard let task = currentTask else { return }

        let returnDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

        Task {
            await writeUserInProgress(task, returnDate: returnDate)
        }

        dailyDoseCompletedCount += 1
        completedThisSession += 1
        currentTask = nil
        showTaskFlow = false
        taskFlowWorkflowId = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    /// StatusCard: "Later" — snoozes task by 3 days, bumps it down the queue.
    func statusActionLater() {
        guard let task = currentTask else { return }

        let snoozedUntil = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

        Task {
            await writeSnooze(task, snoozedUntil: snoozedUntil)
        }

        allActiveTasks.removeAll { $0.id == task.id }
        dailyDoseCompletedCount += 1
        currentTask = nil
        showTaskFlow = false
        taskFlowWorkflowId = nil
        isFocusedTask = false

        advanceAfterTask()
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

    // MARK: - Skip Current Task

    func skipCurrentTask() {
        if let task = currentTask {
            let snoozedUntil = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            Task {
                await writeSnooze(task, snoozedUntil: snoozedUntil)
            }
            allActiveTasks.removeAll { $0.id == task.id }
        }
        dailyDoseCompletedCount += 1
        currentTask = nil
        isFocusedTask = false
        advanceAfterTask()
    }

    // MARK: - Firestore Write

    private func markTaskCompleted(_ task: PeezyCard) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        do {
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(task.id)
                .updateData([
                    "status": "Completed",
                    "completedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("⚠️ Failed to mark task completed in Firestore: \(error.localizedDescription)")
        }
    }

    private func markTaskInProgress(_ task: PeezyCard) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        do {
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(task.id)
                .updateData([
                    "status": "InProgress",
                    "inProgressAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("⚠️ Failed to mark task in progress in Firestore: \(error.localizedDescription)")
        }
    }

    private func writeUserInProgress(_ task: PeezyCard, returnDate: Date) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        do {
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(task.id)
                .updateData([
                    "status": "UserInProgress",
                    "userInProgressDate": Timestamp(date: Date()),
                    "userInProgressReturnDate": Timestamp(date: returnDate)
                ])
        } catch {
            print("⚠️ Failed to mark task as user in progress in Firestore: \(error.localizedDescription)")
        }
    }

    private func writeSnooze(_ task: PeezyCard, snoozedUntil: Date) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        do {
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(task.id)
                .updateData([
                    "status": "Snoozed",
                    "snoozedUntil": Timestamp(date: snoozedUntil),
                    "lastSnoozedAt": FieldValue.serverTimestamp()
                ])
        } catch {
            print("⚠️ Failed to snooze task in Firestore: \(error.localizedDescription)")
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
            let batch = Array(allActiveTasks.prefix(dailyTarget))
            taskQueue = batch
        }
        startNextTask()
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

    // MARK: - Helpers

    private func colorNameForPriority(_ priority: PeezyCard.Priority) -> String {
        switch priority {
        case .urgent: return "red"
        case .high: return "orange"
        case .normal: return "green"
        case .low: return "gray"
        }
    }
}
