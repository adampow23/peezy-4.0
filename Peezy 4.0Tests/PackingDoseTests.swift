import Foundation
import Testing
@testable import Peezy_4_0

struct PackingDoseTests {
    @Test func frozenDoseIncludesAtMostOneDuePackingSession() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let regular = PeezyCard(
            id: "REGULAR",
            type: .task,
            title: "Regular task",
            subtitle: "",
            taskId: "REGULAR",
            urgencyPercentage: 99
        )
        let overdue = packingCard(id: "PACKING_SESSION_1", scheduledDate: yesterday)
        let dueToday = packingCard(id: "PACKING_SESSION_2", scheduledDate: today)
        let future = packingCard(id: "PACKING_SESSION_3", scheduledDate: tomorrow)

        let ids = DailyDoseEngine().taskIdsForNewDose(
            from: [regular, overdue, dueToday, future],
            daysUntilMove: 30,
            today: today,
            calendar: calendar
        )

        #expect(ids == ["PACKING_SESSION_1"])
        #expect(ids.count == 1)
        #expect(ids.filter { $0.hasPrefix("PACKING_SESSION_") }.count == 1)
    }

    @Test func futurePackingSessionDoesNotInflateRegularTarget() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 26))!
        let future = calendar.date(byAdding: .day, value: 4, to: today)!
        let cards = [
            PeezyCard(id: "A", type: .task, title: "A", subtitle: "", taskId: "A"),
            PeezyCard(id: "B", type: .task, title: "B", subtitle: "", taskId: "B"),
            packingCard(id: "PACKING_SESSION_1", scheduledDate: future)
        ]

        let ids = DailyDoseEngine().taskIdsForNewDose(
            from: cards,
            daysUntilMove: 30,
            today: today,
            calendar: calendar
        )

        #expect(ids == ["A"])
    }

    private func packingCard(id: String, scheduledDate: Date) -> PeezyCard {
        let session = PackingSession(
            taskId: id,
            sessionKey: id.lowercased(),
            sourceKeys: [id.lowercased()],
            rooms: ["Kitchen"],
            roomLabel: "Kitchen",
            estMinutes: 40,
            scheduledDate: scheduledDate,
            itemSummary: ["Dishes"],
            isFirstNightBag: false,
            completedAt: nil,
            isBehindPace: false
        )
        return PeezyCard(
            id: id,
            type: .task,
            title: id,
            subtitle: "",
            taskId: id,
            workflowId: "packing_session",
            payload: .packing(session)
        )
    }
}
