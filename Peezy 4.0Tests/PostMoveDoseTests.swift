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

// MARK: - Spec 09 Phase 3: nudge tier

struct NudgeTierTests {
    @Test func mapperDecodesNudgeFixture() {
        let data: [String: Any] = [
            "taskId": "STORAGE_NUDGE",
            "title": "Storage unit",
            "status": "Upcoming",
            "tier": "nudge",
            "nudgePrompt": "Sounds like you might need storage — want us to line it up?",
            "nudgeSpawnsId": "BOOK_STORAGE",
            "notesEnabled": true,
            "quoteTracker": "v1",
            "spawnedFrom": ["kind": "conversation", "id": "MOVING_DAY_PLAN"],
            "onCompleteSpawns": [
                ["id": "RETURN_ISP_EQUIPMENT", "dateRule": ["anchor": "moveDate", "offsetDays": NSNumber(value: 2)]]
            ],
            "urgencyPercentage": NSNumber(value: 60)
        ]

        let card = PeezyCardFirestoreMapper.card(from: data, documentID: "STORAGE_NUDGE")

        #expect(card?.tier == "nudge")
        #expect(card?.nudgePrompt == "Sounds like you might need storage — want us to line it up?")
        #expect(card?.nudgeSpawnsId == "BOOK_STORAGE")
        #expect(card?.notesEnabled == true)
        #expect(card?.quoteTracker == "v1")
        #expect(card?.spawnedFrom == PeezyCard.SpawnedFrom(kind: "conversation", id: "MOVING_DAY_PLAN"))
        #expect(card?.onCompleteSpawns == [
            PeezyCard.CompletionSpawn(
                id: "RETURN_ISP_EQUIPMENT",
                dateRule: PeezyCard.SpawnDateRule(anchor: "moveDate", offsetDays: 2)
            )
        ])
    }

    @Test func mapperDefaultsSpawnFieldsWhenAbsent() {
        let card = PeezyCardFirestoreMapper.card(
            from: ["title": "Plain", "status": "Upcoming"],
            documentID: "PLAIN"
        )

        #expect(card?.tier == "task")
        #expect(card?.nudgePrompt == nil)
        #expect(card?.nudgeSpawnsId == nil)
        #expect(card?.spawnedFrom == nil)
        #expect(card?.onCompleteSpawns.isEmpty == true)
        #expect(card?.notesEnabled == false)
        #expect(card?.quoteTracker == "none")
    }

    @Test func groupingSkipsNudgesAndTerminalNudgeStatuses() {
        var nudge = fixture(id: "NUDGE")
        nudge.tier = "nudge"
        var dismissed = fixture(id: "DISMISSED")
        dismissed.status = .dismissed
        var converted = fixture(id: "CONVERTED")
        converted.status = .converted
        let regular = fixture(id: "REGULAR")

        let groups = TaskGrouping.partition([nudge, dismissed, converted, regular])

        #expect(groups.todo.map(\.id) == ["REGULAR"])
        #expect(groups.snoozed.isEmpty)
        #expect(groups.userInProgress.isEmpty)
        #expect(groups.completed.isEmpty)
    }

    private func fixture(id: String) -> PeezyCard {
        PeezyCard(id: id, type: .task, title: id, subtitle: "", taskId: id, urgencyPercentage: 50)
    }
}

// MARK: - Spec 09 Phase 3: legacy-client gate strip

struct NudgeConditionGateTests {
    @Test func generationStripsRequiresClientV2BeforeEvaluation() {
        let conditions: [String: Any] = [
            "requiresClientV2": ["true"],
            "moveType": ["Local"]
        ]
        let assessment: [String: Any] = ["moveType": "Local"]

        // Legacy clients fail-false on the unknown gate key by design…
        #expect(!TaskConditionParser.evaluateConditions(conditions, against: assessment))

        // …this client strips it and evaluates the remaining conditions.
        let stripped = TaskGenerationService.evaluableConditions(conditions)
        #expect(stripped?["requiresClientV2"] == nil)
        #expect(TaskConditionParser.evaluateConditions(stripped, against: assessment))
    }

    @Test func gateOnlyConditionsBecomeAutoPass() {
        let stripped = TaskGenerationService.evaluableConditions(["requiresClientV2": ["true"]])
        #expect(TaskConditionParser.evaluateConditions(stripped, against: [:]))
    }

    @Test func nilConditionsStayNil() {
        #expect(TaskGenerationService.evaluableConditions(nil) == nil)
        #expect(TaskConditionParser.evaluateConditions(nil, against: [:]))
    }
}
