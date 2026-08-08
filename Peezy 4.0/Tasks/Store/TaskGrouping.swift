import Foundation

enum TaskGrouping {
    struct Groups: Equatable {
        var todo: [PeezyCard]
        var snoozed: [PeezyCard]
        var userInProgress: [PeezyCard]    // "You're on it"
        var peezyOnIt: [PeezyCard]         // Retained for view compatibility; always empty.
        var completed: [PeezyCard]
    }

    /// Partitions tasks into tab sections. `now` parameter for testability.
    static func partition(_ tasks: [PeezyCard], now: Date = Date()) -> Groups {
        var todo: [PeezyCard] = []
        var snoozed: [PeezyCard] = []
        var userInProgress: [PeezyCard] = []
        var completed: [PeezyCard] = []

        for task in tasks {
            // Nudges are Home-only (Spec 09) — never a Tasks-tab row.
            guard task.tier != "nudge" else { continue }
            guard task.status != .skipped else { continue }

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

        let todoSorted = sortPackingSessionsChronologically(
            in: todo.sorted { a, b in
                let ua = a.urgencyPercentage ?? 0
                let ub = b.urgencyPercentage ?? 0
                if ua != ub { return ua > ub }
                return a.title < b.title
            }
        )
        let snoozedSorted = snoozed
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }

        let uipSorted = userInProgress.sorted {
            ($0.userInProgressReturnDate ?? .distantFuture) < ($1.userInProgressReturnDate ?? .distantFuture)
        }

        let completedSorted = completed.sorted { a, b in
            let aDate = a.completedAt ?? .distantPast
            let bDate = b.completedAt ?? .distantPast
            return aDate > bDate
        }

        return Groups(
            todo: todoSorted,
            snoozed: snoozedSorted,
            userInProgress: uipSorted,
            peezyOnIt: [],
            completed: completedSorted
        )
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
