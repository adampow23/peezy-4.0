import Foundation
import Testing
@testable import Peezy_4_0

struct PackingDisplayOrderTests {
    @Test func todoPackingSessionsDisplayInStrictChronologicalOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let cards = [
            packingCard(
                id: "PACKING_SESSION_1",
                title: "Bedroom parts",
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
            ),
            packingCard(
                id: "PACKING_SESSION_3",
                title: "First-night bag",
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 19))!
            ),
            packingCard(
                id: "PACKING_SESSION_2",
                title: "Kitchen essentials",
                date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
            )
        ]

        let displayedDates = TaskGrouping.partition(cards).todo.compactMap {
            $0.packingSession?.scheduledDate
        }

        #expect(displayedDates == displayedDates.sorted())
    }

    private func packingCard(id: String, title: String, date: Date) -> PeezyCard {
        let session = PackingSession(
            taskId: id,
            sessionKey: id.lowercased(),
            sourceKeys: [id.lowercased()],
            rooms: [title],
            roomLabel: title,
            estMinutes: 40,
            scheduledDate: date,
            itemSummary: [title],
            isFirstNightBag: title == "First-night bag",
            completedAt: nil,
            isBehindPace: false
        )

        return PeezyCard(
            id: id,
            type: .task,
            title: title,
            subtitle: "",
            taskId: id,
            workflowId: "packing_session",
            urgencyPercentage: 50,
            payload: .packing(session)
        )
    }
}
