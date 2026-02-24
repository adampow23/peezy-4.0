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
        case welcome
        case activeTask
        case done
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

    /// Count of InProgress tasks for the "all done" screen
    var inProgressTaskCount: Int = 0

    /// Whether the user has opted to get ahead of schedule
    var gettingAhead: Bool = false

    /// Which batch offset we're on: 0 = today, 1 = +1 day ahead, etc.
    var currentBatchOffset: Int = 0

    // MARK: - User Context

    var userState: UserState?
    // MARK: - UserDefaults Keys (private)

    private let kDailyDoseCompletedCount = "peezy.dailyDose.completedCount"
    private let kDailyDoseLastDate = "peezy.dailyDose.lastDate"
    private let kDailyDoseFirstLaunchDate = "peezy.dailyDose.firstLaunchDate"

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

    var welcomeSubtitle: String {
        if let days = userState?.daysUntilMove {
            if days == 0 { return "Moving day is here!" }
            if days == 1 { return "Just 1 day until your move!" }
            if days <= 7 { return "\(days) days until your move." }
        }
        return "Here's what's on your plate today."
    }

    var taskReadyText: String {
        let count = taskQueue.count
        if count == 0 { return "You're all caught up!" }
        if count == 1 { return "1 task ready" }
        return "\(count) tasks ready"
    }

    var welcomeSubtitleForDailyDose: String {
        if gettingAhead {
            return "Here's your next batch."
        }
        return welcomeSubtitle
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

    /// "Today: X of Y done" — shown on welcome card
    var progressText: String {
        let done = min(dailyDoseCompletedCount, dailyTarget)
        return "Today: \(done) of \(dailyTarget) done"
    }

    /// "Z tasks remaining · X days until move" — shown on welcome card
    var dayProgressText: String {
        "\(allActiveTasks.count) tasks remaining · \(daysUntilMoveValue) days until move"
    }

    /// Subtext for the daily celebration card
    var celebrationSubtext: String {
        let aheadDays = currentBatchOffset
        if aheadDays > 0 {
            let unit = aheadDays == 1 ? "day" : "days"
            return "You're \(aheadDays) \(unit) ahead — nice work."
        }
        if daysUntilMoveValue <= bufferDays + 2 {
            return "You're in great shape for move day."
        }
        return "Right on schedule. Enjoy the rest of your day."
    }

    /// Drives which done-card variant is shown
    enum DailyDoseViewState {
        case batchComplete(aheadDays: Int)  // today's batch done, or a get-ahead batch done
        case allTasksDone                   // no active tasks remain
        case normalDone                     // mid-batch completion
    }

    var dailyDoseViewState: DailyDoseViewState {
        if allActiveTasks.isEmpty {
            return .allTasksDone
        }
        if isTodayComplete && !gettingAhead {
            return .batchComplete(aheadDays: currentBatchOffset)
        }
        if gettingAhead && taskQueue.isEmpty {
            return .batchComplete(aheadDays: currentBatchOffset)
        }
        return .normalDone
    }

    // MARK: - Load Tasks from Firestore

    func loadTasks() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run { self.state = .welcome }
            return
        }

        await MainActor.run { self.state = .loading }

        do {
            let db = Firestore.firestore()

            // Same query as PeezyStackViewModel — identical Firestore source
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .whereField("status", in: ["Upcoming", "pending", "Snoozed", "InProgress"])
                .getDocuments()

            var cards: [PeezyCard] = []
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

                // Skip currently snoozed tasks
                if let snoozedUntil = snoozedUntil, snoozedUntil > now { continue }

                let isVendorTask = (data["category"] as? String)?.lowercased().contains("vendor") ?? false
                let cardType: PeezyCard.CardType = isVendorTask ? .vendor : .task

                let card = PeezyCard(
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
                    urgencyPercentage: urgencyPercentage
                )

                if card.shouldShow {
                    cards.append(card)
                }
            }

            // Separate InProgress tasks (counted but not queued)
            let inProgressCards = cards.filter { $0.status == .inProgress }
            let activeCards = cards.filter { $0.status != .inProgress }

            // Sort active tasks: urgencyPercentage DESC, then title ASC for tiebreak
            let sorted = activeCards.sorted { a, b in
                let ua = a.urgencyPercentage ?? 0
                let ub = b.urgencyPercentage ?? 0
                if ua != ub { return ua > ub }
                return a.title < b.title
            }

            await MainActor.run {
                self.taskQueue = sorted
                self.state = .welcome
            }

        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.state = .welcome
            }
        }
    }

    // MARK: - Start Next Task

    /// Pulls the next task from the queue and transitions to activeTask state
    func startNextTask() {
        guard !taskQueue.isEmpty else {
            state = .done
            return
        }

        let task = taskQueue.removeFirst()
        currentTask = task

        // Check if this task has an associated workflow
        if let workflowId = getWorkflowId(for: task) {
            isStartingWorkflow = true
            state = .activeTask

            Task {
                await workflowManager.startWorkflow(
                    workflowId: workflowId,
                    workflowTitle: task.title
                )

                // Set up dismissal handler (user cancelled workflow)
                workflowManager.onWorkflowDismissed = { [weak self] in
                    guard let self = self else { return }
                    // Put task back at front of queue
                    if let task = self.currentTask {
                        self.taskQueue.insert(task, at: 0)
                    }
                    self.currentTask = nil
                    self.isStartingWorkflow = false
                    self.state = .welcome
                }

                await MainActor.run {
                    self.isStartingWorkflow = false
                }
            }
        } else {
            // No workflow — show simple task card
            state = .activeTask
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
        currentTask = nil
        state = .done
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
            state = .welcome
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
                    self.currentTask = nil
                    self.state = .done
                }
            } else {
                await MainActor.run {
                    self.error = self.workflowManager.error ?? "Workflow submission failed"
                }
            }
        }
    }

    // MARK: - Skip Current Task

    /// Puts the current task back at the end of the queue
    func skipCurrentTask() {
        // Demo mode — end demo and return to welcome
        if isDemoWorkflow {
            workflowManager.cancelWorkflow()
            currentTask = nil
            isDemoWorkflow = false
            demoPhase = nil
            state = .welcome
            return
        }

        if isInWorkflow {
            workflowManager.cancelWorkflow()
            // cancelWorkflow triggers onWorkflowDismissed callback which handles state
        } else {
            if let task = currentTask {
                taskQueue.append(task)
            }
            currentTask = nil
            state = .welcome
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
