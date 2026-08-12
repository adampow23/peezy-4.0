import Foundation

enum TaskGrouping {
    struct Groups: Equatable {
        var todo: [PeezyCard]
        var snoozed: [PeezyCard]
        var userInProgress: [PeezyCard]    // "You're on it"
        var peezyOnIt: [PeezyCard]         // Retained for view compatibility; always empty.
        var completed: [PeezyCard]
    }

    /// Partitions tasks into tab sections. `now`/`calendar` parameters for
    /// testability. `moveDate` comes from UserState — the same source the Home
    /// dose path passes to DailyDoseEngine (PeezyHomeViewModel).
    static func partition(
        _ tasks: [PeezyCard],
        moveDate: Date? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Groups {
        var todo: [PeezyCard] = []
        var snoozed: [PeezyCard] = []
        var userInProgress: [PeezyCard] = []
        var completed: [PeezyCard] = []

        let doseGate = DailyDoseEngine()

        for task in tasks {
            // Nudges are Home-only (Spec 09) — never a Tasks-tab row.
            guard task.tier != "nudge" else { continue }
            guard task.status != .skipped else { continue }

            // Post-move surfacing gate — identical semantics to the dose path:
            // a surfaceAfterDaysPastMove row is hidden entirely before
            // moveDate + n, and a missing move date cannot satisfy the gate.
            guard doseGate.isEligibleForDose(task, moveDate: moveDate, today: now, calendar: calendar) else { continue }

            if isSnoozedEffective(task, now: now) {
                snoozed.append(task)
                continue
            }

            switch task.status {
            case .completed:
                completed.append(task)
            case .userInProgress:
                userInProgress.append(task)
            case .inProgress, .pending, .matchingInProgress:
                // Retired human-handoff states are terminal. Normalize the
                // local presentation so old documents appear under Done.
                var completedTask = task
                completedTask.status = .completed
                completed.append(completedTask)
            case .upcoming, .snoozed:
                todo.append(task)
            case .skipped:
                continue
            case .dismissed, .converted:
                // Terminal nudge lifecycle (Spec 09) — hidden everywhere.
                continue
            }
        }

        let todoSorted = sortPackingSessionsChronologically(in: ascending(todo, by: \.dueDate))
        let snoozedSorted = ascending(snoozed, by: \.snoozedUntil)
        let uipSorted = ascending(userInProgress, by: \.userInProgressReturnDate)

        let completedSorted = completed.sorted { a, b in
            let aDate = a.completedAt ?? .distantPast
            let bDate = b.completedAt ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.title < b.title
        }

        return Groups(
            todo: todoSorted,
            snoozed: snoozedSorted,
            userInProgress: uipSorted,
            peezyOnIt: [],
            completed: completedSorted
        )
    }

    /// Deterministic tab ordering: the group's key date ascending, nil dates
    /// last, ties broken by title. To-Do keys off dueDate, Snoozed off
    /// snoozedUntil, In-Progress off userInProgressReturnDate.
    private static func ascending(_ tasks: [PeezyCard], by date: (PeezyCard) -> Date?) -> [PeezyCard] {
        tasks.sorted { a, b in
            let aDate = date(a) ?? .distantFuture
            let bDate = date(b) ?? .distantFuture
            if aDate != bDate { return aDate < bDate }
            return a.title < b.title
        }
    }

    static func isSnoozedEffective(_ card: PeezyCard, now: Date = Date()) -> Bool {
        guard let snoozedUntil = card.snoozedUntil else { return false }
        return snoozedUntil > now
    }

    /// Packing generation owns session dates; the Tasks tab only owns their
    /// display order. Keep non-packing task positions unchanged while replacing
    /// packing slots with sessions ordered by their scheduled date.
    private static func sortPackingSessionsChronologically(in tasks: [PeezyCard]) -> [PeezyCard] {
        let packingSessions = tasks
            .filter(\.isPackingSession)
            .sorted { left, right in
                let leftDate = left.packingSession?.scheduledDate ?? left.dueDate ?? .distantFuture
                let rightDate = right.packingSession?.scheduledDate ?? right.dueDate ?? .distantFuture
                if leftDate != rightDate { return leftDate < rightDate }
                return left.id < right.id
            }

        var packingIndex = 0
        return tasks.map { task in
            guard task.isPackingSession else { return task }
            defer { packingIndex += 1 }
            return packingSessions[packingIndex]
        }
    }
}
