import Foundation

enum TaskGrouping {
    struct Groups: Equatable {
        var todo: [PeezyCard]              // upcoming + snoozed (snoozed at bottom)
        var userInProgress: [PeezyCard]    // "You're on it"
        var peezyOnIt: [PeezyCard]         // "Peezy is on it" — includes .inProgress and .matchingInProgress
        var completed: [PeezyCard]
    }

    /// Partitions tasks into tab sections. `now` parameter for testability.
    static func partition(_ tasks: [PeezyCard], now: Date = Date()) -> Groups {
        var todo: [PeezyCard] = []
        var userInProgress: [PeezyCard] = []
        var peezyOnIt: [PeezyCard] = []
        var completed: [PeezyCard] = []

        for task in tasks {
            guard task.status != .skipped else { continue }

            switch task.status {
            case .completed:
                completed.append(task)
            case .userInProgress:
                userInProgress.append(task)
            case .inProgress, .matchingInProgress:
                peezyOnIt.append(task)
            case .upcoming, .snoozed:
                todo.append(task)
            case .skipped:
                continue
            }
        }

        let upcomingPart = todo.filter { !isSnoozedEffective($0, now: now) }
            .sorted { a, b in
                let ua = a.urgencyPercentage ?? 0
                let ub = b.urgencyPercentage ?? 0
                if ua != ub { return ua > ub }
                return a.title < b.title
            }
        let snoozedPart = todo.filter { isSnoozedEffective($0, now: now) }
            .sorted { ($0.snoozedUntil ?? .distantFuture) < ($1.snoozedUntil ?? .distantFuture) }

        let uipSorted = userInProgress.sorted {
            ($0.userInProgressReturnDate ?? .distantFuture) < ($1.userInProgressReturnDate ?? .distantFuture)
        }

        let peezySorted = peezyOnIt.sorted { a, b in
            if a.priority.rawValue != b.priority.rawValue {
                return a.priority.rawValue > b.priority.rawValue
            }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }

        let completedSorted = completed.sorted { a, b in
            let aDate = a.completedAt ?? .distantPast
            let bDate = b.completedAt ?? .distantPast
            return aDate > bDate
        }

        return Groups(
            todo: upcomingPart + snoozedPart,
            userInProgress: uipSorted,
            peezyOnIt: peezySorted,
            completed: completedSorted
        )
    }

    static func isSnoozedEffective(_ card: PeezyCard, now: Date = Date()) -> Bool {
        if card.status == .snoozed { return true }
        if let snoozedUntil = card.snoozedUntil, snoozedUntil > now { return true }
        return false
    }
}
