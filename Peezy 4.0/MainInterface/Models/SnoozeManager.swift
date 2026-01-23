//
//  SnoozeManager.swift
//  Peezy
//
//  Manages task snoozing - when user swipes left, they pick when to see the task again
//
//  INTEGRATION:
//  Add to PeezyStackViewModel.swift:
//
//    var snoozeManager = SnoozeManager()
//    var isSnoozing: Bool { snoozeManager.isSnoozing }
//
//  In handleSwipe(), intercept .later action:
//
//    case .later:
//        if card.canSnooze {
//            snoozeManager.startSnooze(...)
//        } else {
//            // fallback for non-snoozeable cards
//        }
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - Snooze Swipe Action

/// Actions available on the swipeable snooze card
enum SnoozeSwipeAction {
    case tomorrow   // Swipe right - snooze until tomorrow
    case never      // Swipe left - dismiss permanently
    case other      // Swipe up - show date picker for custom date
}

// MARK: - Snooze Option

struct SnoozeOption: Identifiable, Equatable {
    let id: String
    let label: String
    let sublabel: String?
    let icon: String
    let date: Date

    static func quickOptions(moveDate: Date?, taskDueDate: Date?) -> [SnoozeOption] {
        let calendar = Calendar.current
        let now = DateProvider.shared.now

        var options: [SnoozeOption] = []

        // Tomorrow (always tomorrow, never today)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        options.append(SnoozeOption(
            id: "tomorrow",
            label: "Tomorrow",
            sublabel: formatDate(tomorrow),
            icon: "sunrise.fill",
            date: tomorrow
        ))

        // This Weekend (next Saturday, or next Saturday if today is Sat/Sun)
        if let weekend = nextWeekend() {
            options.append(SnoozeOption(
                id: "weekend",
                label: "This Weekend",
                sublabel: formatDate(weekend),
                icon: "calendar.badge.clock",
                date: weekend
            ))
        }

        // Next Week (7 days from now)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now))!
        options.append(SnoozeOption(
            id: "next_week",
            label: "Next Week",
            sublabel: formatDate(nextWeek),
            icon: "calendar",
            date: nextWeek
        ))

        // In 2 Weeks
        let twoWeeks = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: now))!
        options.append(SnoozeOption(
            id: "two_weeks",
            label: "In 2 Weeks",
            sublabel: formatDate(twoWeeks),
            icon: "calendar.badge.plus",
            date: twoWeeks
        ))

        // Smart option: "Before it's urgent"
        // Calculates a reminder that leaves buffer but creates appropriate pressure
        // Max snooze of 7 days for smart option, or 3 days before due, whichever is sooner
        if let dueDate = taskDueDate {
            let daysUntilDue = calendar.dateComponents([.day], from: now, to: dueDate).day ?? 0

            if daysUntilDue > 5 {
                // Smart calculation: min(7 days from now, 3 days before due)
                let maxSnoozeDays = min(7, daysUntilDue - 3)

                if maxSnoozeDays > 1 {
                    let smartDate = calendar.date(byAdding: .day, value: maxSnoozeDays, to: calendar.startOfDay(for: now))!
                    let daysLeft = daysUntilDue - maxSnoozeDays

                    options.append(SnoozeOption(
                        id: "smart",
                        label: "Before It's Urgent",
                        sublabel: "\(daysLeft) days before due",
                        icon: "brain.head.profile",
                        date: smartDate
                    ))
                }
            }
        }

        return options
    }

    /// Returns next Saturday, handling edge cases:
    /// - If today is Saturday → returns NEXT Saturday (7 days)
    /// - If today is Sunday → returns next Saturday (6 days)
    /// - Otherwise → returns this coming Saturday
    private static func nextWeekend() -> Date? {
        let calendar = Calendar.current
        let now = DateProvider.shared.now
        let today = calendar.startOfDay(for: now)

        // Get current weekday (1 = Sunday, 7 = Saturday)
        let weekday = calendar.component(.weekday, from: today)

        var daysUntilSaturday: Int

        switch weekday {
        case 7: // Saturday - return NEXT Saturday
            daysUntilSaturday = 7
        case 1: // Sunday - return this Saturday (6 days)
            daysUntilSaturday = 6
        default: // Mon-Fri - return this Saturday
            daysUntilSaturday = 7 - weekday
        }

        return calendar.date(byAdding: .day, value: daysUntilSaturday, to: today)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Snooze Card Type

enum SnoozeCard: Identifiable, Equatable {
    case swipeable(taskId: String, taskTitle: String)  // New swipeable card
    case options(taskId: String, taskTitle: String)    // Legacy options list
    case datePicker(taskId: String, taskTitle: String)
    case confirmation(taskTitle: String, snoozeDate: Date, action: SnoozeConfirmAction)

    var id: String {
        switch self {
        case .swipeable(let taskId, _): return "snooze-swipe-\(taskId)"
        case .options(let taskId, _): return "snooze-options-\(taskId)"
        case .datePicker(let taskId, _): return "snooze-picker-\(taskId)"
        case .confirmation(let title, _, _): return "snooze-confirm-\(title)"
        }
    }
}

// Action type for confirmation display
enum SnoozeConfirmAction: Equatable {
    case snoozed    // Tomorrow or custom date
    case dismissed  // Never - removed from list
}

// MARK: - Snooze Manager

@Observable
class SnoozeManager {

    // State
    var isSnoozing = false
    var snoozeCard: SnoozeCard?
    var selectedDate: Date = DateProvider.shared.now.addingTimeInterval(86400) // Default tomorrow
    var isLoading = false
    var error: Error?

    // Context for smart options
    var moveDate: Date?
    var taskDueDate: Date?
    var currentTaskId: String?
    var currentTaskTitle: String?

    // Callbacks
    var onSnoozeComplete: (() -> Void)?
    var onSnoozeCancelled: (() -> Void)?

    private let db = Firestore.firestore()

    // MARK: - Start Snooze Flow

    /// Called when user swipes left on a task
    /// - Parameters:
    ///   - taskId: The task's Firestore document ID (required, non-nil)
    ///   - taskTitle: Display title for the task
    ///   - taskDueDate: When the task is due (for smart option calculation)
    ///   - moveDate: User's move date (for context)
    func startSnooze(taskId: String, taskTitle: String, taskDueDate: Date?, moveDate: Date?) {
        self.currentTaskId = taskId
        self.currentTaskTitle = taskTitle
        self.taskDueDate = taskDueDate
        self.moveDate = moveDate

        // Default to tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: DateProvider.shared.now))!
        self.selectedDate = tomorrow

        // Show swipeable card (new style)
        snoozeCard = .swipeable(taskId: taskId, taskTitle: taskTitle)
        isSnoozing = true
    }

    /// Start with legacy options card (for backwards compatibility)
    func startSnoozeWithOptions(taskId: String, taskTitle: String, taskDueDate: Date?, moveDate: Date?) {
        self.currentTaskId = taskId
        self.currentTaskTitle = taskTitle
        self.taskDueDate = taskDueDate
        self.moveDate = moveDate

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: DateProvider.shared.now))!
        self.selectedDate = tomorrow

        snoozeCard = .options(taskId: taskId, taskTitle: taskTitle)
        isSnoozing = true
    }

    // MARK: - Handle Swipe Actions (New Style)

    /// Handle swipe action from swipeable card
    func handleSwipeAction(_ action: SnoozeSwipeAction) async {
        guard let taskId = currentTaskId else { return }

        switch action {
        case .tomorrow:
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: DateProvider.shared.now))!
            await snoozeTask(taskId: taskId, until: tomorrow, confirmAction: .snoozed)

        case .never:
            await dismissTaskPermanently(taskId: taskId)

        case .other:
            // Show date picker
            await MainActor.run {
                showDatePicker()
            }
        }
    }

    /// Dismiss task permanently (mark as skipped, won't come back)
    private func dismissTaskPermanently(taskId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = NSError(domain: "SnoozeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            // Update task status to skipped
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(taskId)
                .updateData([
                    "status": "Skipped",
                    "skippedAt": Timestamp(date: Date())
                ])

            print("✅ Task '\(currentTaskTitle ?? taskId)' dismissed permanently")

            await MainActor.run {
                // Show confirmation
                self.snoozeCard = .confirmation(
                    taskTitle: self.currentTaskTitle ?? "Task",
                    snoozeDate: Date(),
                    action: .dismissed
                )
                self.isLoading = false
            }

            // Auto-dismiss after showing confirmation
            try? await Task.sleep(nanoseconds: 900_000_000)

            await MainActor.run {
                self.completeSnooze()
            }

        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }

    // MARK: - Handle Selection (Legacy Options)

    /// User selected a quick option
    func selectOption(_ option: SnoozeOption) async {
        guard let taskId = currentTaskId else { return }
        await snoozeTask(taskId: taskId, until: option.date, confirmAction: .snoozed)
    }

    /// User wants to pick a custom date
    func showDatePicker() {
        guard let taskId = currentTaskId, let title = currentTaskTitle else { return }
        snoozeCard = .datePicker(taskId: taskId, taskTitle: title)
    }

    /// User confirmed custom date
    func confirmCustomDate() async {
        guard let taskId = currentTaskId else { return }
        await snoozeTask(taskId: taskId, until: selectedDate, confirmAction: .snoozed)
    }

    // MARK: - Snooze Task

    /// Updates task in Firestore with snooze date
    private func snoozeTask(taskId: String, until date: Date, confirmAction: SnoozeConfirmAction = .snoozed) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = NSError(domain: "SnoozeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
            return
        }

        await MainActor.run {
            isLoading = true
        }

        do {
            // Update task in Firestore
            try await db.collection("users")
                .document(userId)
                .collection("tasks")
                .document(taskId)
                .updateData([
                    "snoozedUntil": Timestamp(date: date),
                    "status": "Snoozed",
                    "lastSnoozedAt": Timestamp(date: Date())
                ])

            print("✅ Task '\(currentTaskTitle ?? taskId)' snoozed until \(date)")

            await MainActor.run {
                // Show confirmation briefly
                self.snoozeCard = .confirmation(
                    taskTitle: self.currentTaskTitle ?? "Task",
                    snoozeDate: date,
                    action: confirmAction
                )
                self.isLoading = false
            }

            // Auto-dismiss after showing confirmation (0.9 seconds)
            try? await Task.sleep(nanoseconds: 900_000_000)

            await MainActor.run {
                self.completeSnooze()
            }

        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
            }
        }
    }

    // MARK: - Cancel / Complete

    func cancelSnooze() {
        isSnoozing = false
        snoozeCard = nil
        currentTaskId = nil
        currentTaskTitle = nil
        onSnoozeCancelled?()
    }

    private func completeSnooze() {
        isSnoozing = false
        snoozeCard = nil
        currentTaskId = nil
        currentTaskTitle = nil
        onSnoozeComplete?()
    }

    // MARK: - Get Quick Options

    var quickOptions: [SnoozeOption] {
        SnoozeOption.quickOptions(moveDate: moveDate, taskDueDate: taskDueDate)
    }
}
