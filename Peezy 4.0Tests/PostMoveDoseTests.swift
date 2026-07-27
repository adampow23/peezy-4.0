import Foundation
import Testing
@testable import Peezy_4_0

struct PostMoveDoseTests {
    @Test func checkInAppearsOnlyOnOrAfterPostMoveGate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let moveDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let gateDate = calendar.date(byAdding: .day, value: 1, to: moveDate)!
        let engine = DailyDoseEngine()
        let regular = card(id: "REGULAR", urgency: 50)
        let checkIn = card(id: "MOVE_CHECKIN", urgency: 99, surfaceAfterDaysPastMove: 1)

        let moveDayIds = engine.taskIdsForNewDose(
            from: [checkIn, regular],
            daysUntilMove: 0,
            moveDate: moveDate,
            today: moveDate,
            calendar: calendar
        )
        let gateDayIds = engine.taskIdsForNewDose(
            from: [checkIn, regular],
            daysUntilMove: -1,
            moveDate: moveDate,
            today: gateDate,
            calendar: calendar
        )

        #expect(moveDayIds == ["REGULAR"])
        #expect(gateDayIds == ["MOVE_CHECKIN", "REGULAR"])
    }

    @Test func boxReturnWaitsSevenDaysAndMissingMoveDateCannotOpenGate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let moveDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let daySix = calendar.date(byAdding: .day, value: 6, to: moveDate)!
        let daySeven = calendar.date(byAdding: .day, value: 7, to: moveDate)!
        let boxReturn = card(id: "BOX_RETURN", urgency: 90, surfaceAfterDaysPastMove: 7)
        let engine = DailyDoseEngine()

        #expect(!engine.isEligibleForDose(
            boxReturn,
            moveDate: moveDate,
            today: daySix,
            calendar: calendar
        ))
        #expect(engine.isEligibleForDose(
            boxReturn,
            moveDate: moveDate,
            today: daySeven,
            calendar: calendar
        ))
        #expect(!engine.isEligibleForDose(
            boxReturn,
            moveDate: nil,
            today: daySeven,
            calendar: calendar
        ))
    }

    private func card(
        id: String,
        urgency: Int,
        surfaceAfterDaysPastMove: Int? = nil
    ) -> PeezyCard {
        PeezyCard(
            id: id,
            type: .task,
            title: id,
            subtitle: "",
            taskId: id,
            urgencyPercentage: urgency,
            surfaceAfterDaysPastMove: surfaceAfterDaysPastMove
        )
    }
}
