import Foundation

enum TaskGrouping {
    struct Groups: Equatable {
        var todo: [PeezyCard]
        var snoozed: [PeezyCard]
        var userInProgress: [PeezyCard]    // "You're on it"
        var peezyOnIt: [PeezyCard]         // Server-owned lifecycle rows are read-only here.
        var completed: [PeezyCard]

        /// The To-Do tab's single continuous list: todo + snoozed merged,
        /// ordered by the date each row displays — snoozedUntil for snoozed
        /// rows, dueDate otherwise.
        var todoDisplay: [PeezyCard] {
            TaskGrouping.mergedTodoDisplay(todo: todo, snoozed: snoozed)
        }
    }

    /// Partitions tasks into tab sections. `now` parameter for testability.
    static func partition(
        _ tasks: [PeezyCard],
        now: Date = Date()
    ) -> Groups {
        var todo: [PeezyCard] = []
        var snoozed: [PeezyCard] = []
        var userInProgress: [PeezyCard] = []
        var peezyOnIt: [PeezyCard] = []
        var completed: [PeezyCard] = []

        for task in tasks {
            // Nudges are Home-only (Spec 09) — never a Tasks-tab row.
            guard task.tier != "nudge" else { continue }
            guard task.status != .skipped else { continue }

            if task.dispositionContract != nil {
                if task.dispositionContractIsCoherent,
                   task.status == .completed || task.status == .dismissed {
                    completed.append(task)
                } else {
                    peezyOnIt.append(task)
                }
                continue
            }

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
        let peezySorted = peezyOnIt.sorted {
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }

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
            peezyOnIt: peezySorted,
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

    /// Merges the To-Do and Snoozed piles into one list sorted ascending by
    /// the effective date the row displays (snoozedUntil for snoozed rows,
    /// dueDate otherwise), nil dates last, title tiebreak. Packing sessions
    /// keep their chronological slot ordering within the merged list.
    static func mergedTodoDisplay(todo: [PeezyCard], snoozed: [PeezyCard]) -> [PeezyCard] {
        let keyed: [(card: PeezyCard, date: Date?)] =
            todo.map { ($0, $0.dueDate) } + snoozed.map { ($0, $0.snoozedUntil) }
        let merged = keyed.sorted { a, b in
            let aDate = a.date ?? .distantFuture
            let bDate = b.date ?? .distantFuture
            if aDate != bDate { return aDate < bDate }
            return a.card.title < b.card.title
        }
        return sortPackingSessionsChronologically(in: merged.map(\.card))
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
