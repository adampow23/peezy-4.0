//
//  PeezyHomeViewModel.swift
//  Peezy
//
//  State machine view model for the main home screen.
//  Replaces PeezyStackViewModel for the home tab.
//
//  States: loading → welcome → activeTask → done
//
//  Dependencies:
//  - WorkflowManager (existing, unchanged)
//  - WorkflowService (existing, unchanged)
//  - PeezyCard (existing, unchanged)
//  - UserState (existing, unchanged)
//  - FirebaseFirestore, FirebaseAuth
//

import SwiftUI
import Observation
import FirebaseFirestore
import FirebaseAuth

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

    // MARK: - Workflow Support

    var workflowManager = WorkflowManager()
    var isInWorkflow: Bool { workflowManager.isInWorkflow }

    /// Guards against the gap between calling startWorkflow and WorkflowManager setting isLoading
    var isStartingWorkflow: Bool = false

    // MARK: - Demo Workflow

    enum DemoPhase: Equatable {
        case intro
        case question(index: Int)
        case recap
    }

    /// Current demo phase — view observes this directly for tooltip display
    var demoPhase: DemoPhase? = nil
    var isDemoWorkflow = false

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
        return "Based on your move date, knocking out about \(daily) per day will keep you right on track.\n\nEach day, we'll serve up the tasks that matter most — just work through them and you're golden.\n\nIf you're feeling motivated and want to get ahead, go for it.\n\nIn the menu (top left), you'll find your full task list and move details. Feel free to update anything as plans change.\n\nAnd if you ever have a question about anything, just swipe up and ask!"
    }

    var firstTimeWelcomeGreeting: String {
        let name = userState?.name ?? ""
        return name.isEmpty ? "Welcome!" : "Welcome, \(name)!"
    }

    // MARK: - Daily Greeting Text

    var dailyGreetingSubtitle: String {
        return "Just \(dailyTarget) to knock out today!"
    }

    // MARK: - Returning Mid-Day Text

    var returningMidDaySubtitle: String {
        let completed = dailyDoseCompletedCount
        let remaining = max(dailyTarget - completed, 0)
        return "You've done \(completed) of \(dailyTarget) today — \(remaining) to go."
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

    /// Calendar day number we're on in the plan (1-indexed)
    var dayNumber: Int {
        let firstLaunchStr = UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) ?? todayISOString()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let firstDate = formatter.date(from: firstLaunchStr) else { return 1 }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: firstDate, to: Date()).day ?? 0
        return days + 1
    }

    /// Approximate total plan days (elapsed + remaining)
    var totalPlanDays: Int {
        dayNumber + daysUntilMoveValue
    }

    /// "Today: X of Y done" — shown on welcome card (daily count only, no total)
    var progressText: String {
        let done = min(dailyDoseCompletedCount, dailyTarget)
        return "Today: \(done) of \(dailyTarget) done"
    }

    /// Subtext for the daily complete card
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

    /// Text for the allComplete card
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

            // Same query as PeezyStackViewModel — identical Firestore source
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

                // Skip completed/skipped (shouldn't match query, but guard)
                if status == .completed || status == .skipped { continue }

                // Parse priority
                let priorityString = data["priority"] as? String ?? "Medium"
                let priority: PeezyCard.Priority
                switch priorityString.lowercased() {
                case "high", "urgent": priority = .high
                case "low": priority = .low
                default: priority = .normal
                }

                // Parse dates
                let dueDate = (data["dueDate"] as? Timestamp)?.dateValue()
                let snoozedUntil = (data["snoozedUntil"] as? Timestamp)?.dateValue()
                let lastSnoozedAt = (data["lastSnoozedAt"] as? Timestamp)?.dateValue()
                let urgencyPercentage = (data["urgencyPercentage"] as? NSNumber)?.intValue
                let userInProgressDate = (data["userInProgressDate"] as? Timestamp)?.dateValue()
                let userInProgressReturnDate = (data["userInProgressReturnDate"] as? Timestamp)?.dateValue()

                // Skip currently snoozed tasks
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
                    urgencyPercentage: urgencyPercentage,
                    userInProgressDate: userInProgressDate,
                    userInProgressReturnDate: userInProgressReturnDate
                )

                if card.status == .inProgress {
                    inProgressBuffer.append(card)
                } else if card.status == .userInProgress {
                    // UserInProgress: if return date has passed, put back in queue
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

            // Separate InProgress and UserInProgress tasks (counted but not queued)
            let inProgressCards = inProgressBuffer
            let userInProgressCards = userInProgressBuffer
            let activeCards = cards

            // Sort active tasks: urgencyPercentage DESC, then title ASC for tiebreak
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
                // Slice to today's batch only
                let batch = Array(sorted.prefix(self.dailyTarget))
                self.taskQueue = batch
                // Determine which state to show
                self.determineHomeState()
            }

            // Patch any stale task docs missing workflowId — also updates in-memory cards immediately
            Task {
                await self.migrateWorkflowIds(tasks: snapshot.documents)
                // Also patch in-memory cards
                let workflowMapping: [String: String] = [
                    "BOOK_MOVERS": "book_movers",
                    "BOOK_CLEANERS": "book_cleaners",
                    "SETUP_INTERNET": "setup_internet",
                    "RENT_TRUCK": "rent_truck"
                ]
                await MainActor.run {
                    for i in self.taskQueue.indices {
                        if self.taskQueue[i].workflowId == nil,
                           let mapped = workflowMapping[self.taskQueue[i].taskId ?? ""] {
                            self.taskQueue[i].workflowId = mapped
                        }
                    }
                    if var current = self.currentTask,
                       current.workflowId == nil,
                       let mapped = workflowMapping[current.taskId ?? ""] {
                        current.workflowId = mapped
                        self.currentTask = current
                    }
                }
            }

        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.state = .dailyGreeting
            }
        }
    }

    // MARK: - Start Next Task

    /// Pulls the next task from the queue and transitions to activeTask state
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

        if getWorkflowId(for: task) != nil {
            startWorkflowForCurrentTask()
        } else {
            // No workflow — show simple task card
            state = .activeTask
        }
    }

    // MARK: - Advance After Task

    /// Called after any task action (complete, snooze, I'm on it).
    /// If the daily quota is met, returns to dailyComplete instead of auto-serving the next task.
    private func advanceAfterTask() {
        if allActiveTasks.isEmpty {
            currentTask = nil
            isFocusedTask = false
            state = .allComplete
        } else if dailyDoseCompletedCount >= dailyTarget {
            // Quota met — return to celebration/keep-going screen
            currentTask = nil
            isFocusedTask = false
            state = .dailyComplete
        } else if !taskQueue.isEmpty {
            // Still working through daily dose
            startNextTask()
        } else {
            // Queue empty but quota not met — recalculate
            determineHomeState()
        }
    }

    /// Start or restart the workflow for currentTask — does NOT dequeue from taskQueue.
    /// Used both by startNextTask() and by the simpleTaskCard retry button.
    func startWorkflowForCurrentTask() {
        guard let task = currentTask,
              let workflowId = getWorkflowId(for: task) else {
            // Fallback: task has no workflow, just show as active
            print("🔴 startWorkflowForCurrentTask: no workflowId found, falling back to activeTask")
            state = .activeTask
            return
        }

        print("🔴 Starting workflow: \(workflowId)")
        isStartingWorkflow = true
        state = .activeTask

        Task {
            await workflowManager.startWorkflow(
                workflowId: workflowId,
                workflowTitle: task.title
            )

            let started = workflowManager.isInWorkflow
            print("🔴 Workflow started: \(started)")
            if !started {
                print("🔴 Workflow FAILED to start. Error: \(workflowManager.error ?? "nil")")
            }

            // Set up dismissal handler (user cancelled workflow)
            workflowManager.onWorkflowDismissed = { [weak self] in
                guard let self = self else { return }
                // Put task back at front of queue
                if let task = self.currentTask {
                    self.taskQueue.insert(task, at: 0)
                }
                self.currentTask = nil
                self.isStartingWorkflow = false
                self.isFocusedTask = false
                self.determineHomeState()
            }

            await MainActor.run {
                self.isStartingWorkflow = false
            }
        }
    }

    // MARK: - Complete Simple Task

    /// Marks the current non-workflow task as completed
    func completeCurrentTask() {
        guard let task = currentTask else { return }

        Task {
            await markTaskCompleted(task)
        }

        completedThisSession += 1
        dailyDoseCompletedCount += 1
        allActiveTasks.removeAll { $0.id == task.id }
        currentTask = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    // MARK: - Mark Task User In Progress ("I'm on it")

    /// Marks the current task as UserInProgress — user is handling it themselves.
    /// Task returns to the card stack after 3 days.
    func markCurrentTaskUserInProgress() {
        guard let task = currentTask else { return }

        let returnDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

        Task {
            await writeUserInProgress(task, returnDate: returnDate)
        }

        dailyDoseCompletedCount += 1
        completedThisSession += 1
        // UserInProgress tasks stay in allActiveTasks count (they'll come back)
        currentTask = nil
        isFocusedTask = false

        advanceAfterTask()
    }

    // MARK: - Focus Task (from Task List)

    /// Loads a specific task as the current task, called when user taps Start in task list.
    func focusTask(_ task: PeezyCard) {
        // Remove from queue if present
        taskQueue.removeAll { $0.id == task.id }
        currentTask = task
        isFocusedTask = true

        if getWorkflowId(for: task) != nil {
            startWorkflowForCurrentTask()
        } else {
            state = .activeTask
        }
    }

    // MARK: - Complete Workflow Task

    /// Called when user taps submit on workflow recap card
    func completeWorkflowTask() {
        // Demo mode — skip Firebase, just reset
        if isDemoWorkflow {
            workflowManager.cancelWorkflow()
            currentTask = nil
            isDemoWorkflow = false
            demoPhase = nil
            isFocusedTask = false
            determineHomeState()
            return
        }

        guard let task = currentTask,
              let userId = Auth.auth().currentUser?.uid else {
            error = "User not authenticated"
            return
        }

        Task {
            let success = await workflowManager.completeWorkflow(userId: userId)

            if success {
                await markTaskInProgress(task)
                await MainActor.run {
                    self.completedThisSession += 1
                    self.dailyDoseCompletedCount += 1
                    self.allActiveTasks.removeAll { $0.id == task.id }
                    self.currentTask = nil
                    self.isFocusedTask = false
                    self.advanceAfterTask()
                }
            } else {
                await MainActor.run {
                    self.error = self.workflowManager.error ?? "Workflow submission failed"
                }
            }
        }
    }

    // MARK: - Get Ahead

    /// Called when user taps "Want to get ahead?" or "Keep going?"
    /// Loads the next day's batch of tasks into taskQueue.
    /// Called when user taps "Get ahead" — loads ONE additional task.
    func getAhead() {
        gettingAhead = true

        // Find the next most urgent task not already in taskQueue
        let queueIds = Set(taskQueue.map { $0.id })
        let nextTask = allActiveTasks
            .sorted { ($0.urgencyPercentage ?? 0) > ($1.urgencyPercentage ?? 0) }
            .first { !queueIds.contains($0.id) }

        if let task = nextTask {
            taskQueue = [task]
            startNextTask()
        } else {
            // No more tasks available
            state = .allComplete
        }
    }

    // MARK: - Skip Current Task

    /// Puts the current task back at the end of the queue
    func skipCurrentTask() {
        // Demo mode — end demo and return to greeting
        if isDemoWorkflow {
            workflowManager.cancelWorkflow()
            currentTask = nil
            isDemoWorkflow = false
            demoPhase = nil
            determineHomeState()
            return
        }

        if isInWorkflow {
            workflowManager.cancelWorkflow()
            // cancelWorkflow triggers onWorkflowDismissed callback which handles state
        } else {
            if let task = currentTask {
                // Snooze the task in Firestore
                let snoozedUntil = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                Task {
                    await writeSnooze(task, snoozedUntil: snoozedUntil)
                }
                // Remove from allActiveTasks (it's snoozed now)
                allActiveTasks.removeAll { $0.id == task.id }
            }
            dailyDoseCompletedCount += 1
            currentTask = nil
            isFocusedTask = false
            advanceAfterTask()
        }
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
            // Log but don't block — task was already removed from queue
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

    // MARK: - Workflow ID Migration

    /// Migrate stale user task docs that are missing workflowId.
    /// Looks up the expected workflowId from a hardcoded catalog mapping and patches
    /// Firestore in place. No-op if the field is already set.
    /// Call from loadTasks() — patches Firestore so future loads are correct.
    private func migrateWorkflowIds(tasks: [QueryDocumentSnapshot]) async {
        let workflowMapping: [String: String] = [
            "BOOK_MOVERS": "book_movers",
            "BOOK_CLEANERS": "book_cleaners",
            "SETUP_INTERNET": "setup_internet",
            "RENT_TRUCK": "rent_truck"
        ]

        for doc in tasks {
            let data = doc.data()
            let taskId = data["taskId"] as? String ?? doc.documentID

            // If task should have workflowId but doesn't
            if let expectedWorkflowId = workflowMapping[taskId],
               data["workflowId"] == nil || (data["workflowId"] as? String)?.isEmpty == true {
                try? await doc.reference.updateData(["workflowId": expectedWorkflowId])
            }
        }
    }

    // MARK: - Workflow Detection

    func getWorkflowId(for card: PeezyCard) -> String? {
        // Read workflowId directly from the card (set from catalog field)
        guard let workflowId = card.workflowId, !workflowId.isEmpty else {
            return nil
        }
        return workflowId
    }

    // MARK: - Workflow Action Forwarding

    func handleWorkflowContinue() {
        workflowManager.progressToNext()

        // Update demo phase based on what progressToNext() produced
        if isDemoWorkflow, let card = workflowManager.workflowCards.first {
            switch card.cardType {
            case .question:
                demoPhase = .question(index: card.questionIndex ?? 0)
            case .recap:
                demoPhase = .recap
            default:
                break
            }
        }
    }

    func handleWorkflowSelect(questionId: String, optionId: String, isExclusive: Bool) {
        workflowManager.selectOption(questionId: questionId, optionId: optionId, isExclusive: isExclusive)
    }

    // MARK: - Demo Workflow Data & Start

    private static let demoQualifying = WorkflowQualifying(
        workflowId: "demo_book_movers",
        intro: WorkflowIntro(
            title: "Let's find you the right movers",
            subtitle: "A few quick questions to match you with companies that fit your move."
        ),
        questions: [
            WorkflowQuestion(
                id: "priority",
                question: "What matters most to you?",
                options: [
                    QuestionOption(id: "price", label: "Lowest Price", icon: "dollarsign.circle.fill"),
                    QuestionOption(id: "reviews", label: "Best Reviews", icon: "star.fill"),
                    QuestionOption(id: "speed", label: "Fastest Available", icon: "clock.fill"),
                    QuestionOption(id: "full_service", label: "Full Service", icon: "hands.sparkles.fill")
                ],
                type: .single_select
            ),
            WorkflowQuestion(
                id: "special_items",
                question: "Any of these items?",
                subtitle: "These need special handling",
                options: [
                    QuestionOption(id: "piano", label: "Piano", icon: "pianokeys"),
                    QuestionOption(id: "art", label: "Art/Antiques", icon: "photo.artframe"),
                    QuestionOption(id: "none", label: "None of These", icon: "checkmark.circle.fill", exclusive: true)
                ],
                type: .multi_select
            )
        ],
        recap: WorkflowRecap(
            title: "Got it. Here's what I heard:",
            closing: "We'll reach out to the top 3 companies based on your answers and get quotes from all of them.",
            button: "Sounds Good"
        )
    )

    func startDemoWorkflow() {
        isDemoWorkflow = true
        demoPhase = .intro

        currentTask = PeezyCard(
            id: "demo_task",
            type: .task,
            title: "Book Movers",
            subtitle: "Find the right movers for your move",
            colorName: "blue",
            taskId: "demo_task",
            workflowId: "demo_book_movers"
        )

        workflowManager.startDemoWorkflow(
            workflowId: "demo_book_movers",
            workflowTitle: "Book Movers",
            qualifying: Self.demoQualifying
        )

        state = .activeTask
    }

    // MARK: - State Determination

    /// Determines which home state to show based on user progress and time of day.
    func determineHomeState() {
        // Don't override state when user navigated here from the task list
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

        state = .dailyGreeting // fallback
    }

    /// Marks first-time welcome as seen and advances to the next state.
    func dismissFirstTimeWelcome() {
        UserDefaults.standard.set(true, forKey: kHasSeenFirstTimeWelcome)
        // Start the first daily batch
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
        // Set first launch date once
        if UserDefaults.standard.string(forKey: kDailyDoseFirstLaunchDate) == nil {
            UserDefaults.standard.set(today, forKey: kDailyDoseFirstLaunchDate)
        }
    }

    /// Called from onAppear to handle the overnight case (app was not restarted between days)
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
