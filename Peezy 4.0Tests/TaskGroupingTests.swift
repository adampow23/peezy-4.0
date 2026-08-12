import Foundation
import Testing
@testable import Peezy_4_0

struct TaskGroupingTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    @Test func todoSortsByDueDateAscendingWithNilLastAndTitleTiebreak() {
        let day = { (offset: Int) -> Date in
            self.calendar.date(from: DateComponents(year: 2026, month: 8, day: 1 + offset))!
        }
        let noDue = card(id: "NO_DUE", title: "Zeta")
        let late = card(id: "LATE", title: "Late", dueDate: day(5))
        let earlyB = card(id: "EARLY_B", title: "Bravo", dueDate: day(1))
        let earlyA = card(id: "EARLY_A", title: "Alpha", dueDate: day(1))

        let groups = TaskGrouping.partition(
            [noDue, late, earlyB, earlyA],
            now: day(0)
        )

        #expect(groups.todo.map(\.id) == ["EARLY_A", "EARLY_B", "LATE", "NO_DUE"])
    }

    @Test func snoozedSortsBySnoozedUntilAscendingWithTitleTiebreak() {
        let day = { (offset: Int) -> Date in
            self.calendar.date(from: DateComponents(year: 2026, month: 8, day: 1 + offset))!
        }
        // dueDates run opposite to snoozedUntil to prove the sort key.
        let later = card(id: "LATER", title: "Later", dueDate: day(1), snoozedUntil: day(5))
        let soonB = card(id: "SOON_B", title: "Bravo", dueDate: day(3), snoozedUntil: day(2))
        let soonA = card(id: "SOON_A", title: "Alpha", dueDate: day(4), snoozedUntil: day(2))

        let groups = TaskGrouping.partition(
            [later, soonB, soonA],
            now: day(0)
        )

        #expect(groups.snoozed.map(\.id) == ["SOON_A", "SOON_B", "LATER"])
        #expect(groups.todo.isEmpty)
    }

    @Test func inProgressSortsByReturnDateAscendingWithNilLastAndTitleTiebreak() {
        let day = { (offset: Int) -> Date in
            self.calendar.date(from: DateComponents(year: 2026, month: 8, day: 1 + offset))!
        }
        // Title "Aardvark" sorts first alphabetically; nil return date must
        // still place it last. dueDates run opposite to prove the sort key.
        let noReturn = card(id: "NO_RETURN", title: "Aardvark", status: .userInProgress, dueDate: day(1))
        let late = card(id: "LATE", title: "Late", status: .userInProgress, dueDate: day(2), userInProgressReturnDate: day(6))
        let earlyB = card(id: "EARLY_B", title: "Bravo", status: .userInProgress, dueDate: day(3), userInProgressReturnDate: day(2))
        let earlyA = card(id: "EARLY_A", title: "Alpha", status: .userInProgress, dueDate: day(4), userInProgressReturnDate: day(2))

        let groups = TaskGrouping.partition(
            [noReturn, late, earlyB, earlyA],
            now: day(0)
        )

        #expect(groups.userInProgress.map(\.id) == ["EARLY_A", "EARLY_B", "LATE", "NO_RETURN"])
    }

    @Test func futurePostMoveCardIncludedAndSortsLastByDueDate() {
        let day = { (offset: Int) -> Date in
            self.calendar.date(from: DateComponents(year: 2026, month: 8, day: 1 + offset))!
        }
        // Post-move gated cards (surfaceAfterDaysPastMove) are Home-dose-only
        // hiding; the Tasks tab shows them, sorted by their post-move dueDate.
        let boxReturn = card(id: "BOX_RETURN", title: "Box return", dueDate: day(17), surfaceAfterDaysPastMove: 7)
        let regular = card(id: "REGULAR", title: "Regular", dueDate: day(1))

        let groups = TaskGrouping.partition(
            [boxReturn, regular],
            now: day(0)
        )

        #expect(groups.todo.map(\.id) == ["REGULAR", "BOX_RETURN"])
        #expect(groups.todoDisplay.map(\.id) == ["REGULAR", "BOX_RETURN"])
    }

    @Test func todoDisplayMergesSnoozedBySnoozedUntilWithNilLastAndTitleTiebreak() {
        let day = { (offset: Int) -> Date in
            self.calendar.date(from: DateComponents(year: 2026, month: 8, day: 1 + offset))!
        }
        let alpha = card(id: "ALPHA", title: "Alpha", dueDate: day(1))
        // Snoozed rows key off snoozedUntil — dueDate runs late to prove it.
        let sched = card(id: "SCHED", title: "Sched", dueDate: day(9), snoozedUntil: day(2))
        let charlie = card(id: "CHARLIE", title: "Charlie", dueDate: day(3))
        // Same effective date across piles → title tiebreak (Bravo < Delta).
        let bravo = card(id: "BRAVO", title: "Bravo", dueDate: day(9), snoozedUntil: day(4))
        let delta = card(id: "DELTA", title: "Delta", dueDate: day(4))
        let noDue = card(id: "NO_DUE", title: "Zeta")

        let groups = TaskGrouping.partition(
            [noDue, delta, bravo, charlie, sched, alpha],
            now: day(0)
        )

        #expect(groups.todoDisplay.map(\.id) == ["ALPHA", "SCHED", "CHARLIE", "BRAVO", "DELTA", "NO_DUE"])
        // The underlying piles are unchanged — tab counts stay the same.
        #expect(groups.todo.count == 4)
        #expect(groups.snoozed.count == 2)
    }

    private func card(
        id: String,
        title: String,
        status: TaskStatus = .upcoming,
        dueDate: Date? = nil,
        snoozedUntil: Date? = nil,
        surfaceAfterDaysPastMove: Int? = nil,
        userInProgressReturnDate: Date? = nil
    ) -> PeezyCard {
        PeezyCard(
            id: id,
            type: .task,
            title: title,
            subtitle: "",
            taskId: id,
            status: status,
            dueDate: dueDate,
            snoozedUntil: snoozedUntil,
            surfaceAfterDaysPastMove: surfaceAfterDaysPastMove,
            userInProgressReturnDate: userInProgressReturnDate
        )
    }
}
