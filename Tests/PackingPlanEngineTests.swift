import Foundation

// Standalone unit tests for the pure packing-plan engine. Run with:
// xcrun swiftc PackingConstants.swift PackingPlanEngine.swift \
//   Tests/PackingPlanEngineTests.swift -o /tmp/peezy_packing_tests && /tmp/peezy_packing_tests

@main
struct PackingPlanEngineTests {
    static func main() {
        var failures: [String] = []
        var checksRun = 0

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checksRun += 1
            if condition() {
                print("PASS  \(name)")
            } else {
                failures.append(name)
                print("FAIL  \(name)")
            }
        }

        let calendar = utcCalendar()
        let today = date(2026, 7, 26, calendar: calendar)
        let roomyMoveDate = date(2026, 8, 20, calendar: calendar)
        let rooms = orderedFixtureRooms()

        let ordered = PackingPlanEngine.generate(
            rooms: rooms,
            moveDate: roomyMoveDate,
            today: today,
            calendar: calendar
        )
        let labels = ordered.sessions.map(\.roomLabel)
        check(labels.first == "Storage", "storage/seasonal is first")
        check(index(ofPrefix: "Living Room", in: labels) < index(ofPrefix: "Guest Room", in: labels), "decor/books precedes guest/spare")
        check(index(ofPrefix: "Guest Room", in: labels) < index(ofPrefix: "Garage", in: labels), "guest/spare precedes garage")
        check(index(ofPrefix: "Garage", in: labels) < index(ofPrefix: "Bedroom 2", in: labels), "garage precedes secondary bedrooms")
        check(index(ofPrefix: "Bedroom 2", in: labels) < index(ofPrefix: "Kitchen non-essentials", in: labels), "secondary bedrooms precede kitchen non-essentials")
        check(index(ofPrefix: "Kitchen non-essentials", in: labels) < index(ofPrefix: "Primary Bedroom", in: labels), "kitchen non-essentials precede primary bedroom")
        check(index(ofPrefix: "Primary Bedroom", in: labels) < index(ofPrefix: "Bathroom", in: labels), "primary bedroom precedes bathrooms")
        check(index(ofPrefix: "Bathroom", in: labels) < index(ofPrefix: "Kitchen essentials", in: labels), "bathrooms precede kitchen essentials")
        check(ordered.sessions.last?.isFirstNightBag == true, "first-night bag is last")
        check(ordered.sessions.last?.sourceKeys == ["first_night_bag"], "first-night bag stays standalone")

        let expectedLastDate = calendar.date(byAdding: .day, value: -1, to: roomyMoveDate)!
        check(ordered.sessions.last?.scheduledDate == expectedLastDate, "reverse schedule ends at moveDate-1")
        check(zip(ordered.sessions, ordered.sessions.dropFirst()).allSatisfy { $0.scheduledDate <= $1.scheduledDate }, "reverse schedule is chronological")
        check(Set(ordered.sessions.map(\.scheduledDate)).count == ordered.sessions.count, "enough days produce one session per date")

        let shortMoveDate = date(2026, 7, 30, calendar: calendar)
        let short = PackingPlanEngine.generate(
            rooms: rooms,
            moveDate: shortMoveDate,
            today: today,
            calendar: calendar
        )
        let availableDays = calendar.dateComponents(
            [.day], from: today,
            to: calendar.date(byAdding: .day, value: -1, to: shortMoveDate)!
        ).day! + 1
        check(short.sessions.count <= availableDays, "short timeline merges to available days")
        check(short.sessions.last?.isFirstNightBag == true, "merge never absorbs first-night bag")
        let fixtureNames = Set(rooms.flatMap(\.items).map(\.name))
        let mergedSummary = short.sessions.flatMap(\.itemSummary).joined(separator: " ")
        check(fixtureNames.allSatisfy(mergedSummary.contains), "merge drops no inventory summary")

        var stale = ordered
        let staleDate = calendar.date(byAdding: .day, value: -2, to: today)!
        for index in stale.sessions.indices {
            stale.sessions[index] = replacing(stale.sessions[index], scheduledDate: staleDate)
        }
        let reflowed = PackingPlanEngine.reflowIfNeeded(stale, today: today, calendar: calendar)
        check(reflowed.reflowedAt == today, "past-dated sessions trigger reflow")
        check(reflowed.sessions.allSatisfy { $0.scheduledDate >= today }, "reflow leaves no incomplete overdue session")
        check(reflowed.sessions.last?.isFirstNightBag == true, "reflow preserves first-night ordering")

        let compressedMoveDate = calendar.date(byAdding: .day, value: 3, to: today)!
        var compressed = ordered
        compressed = PackingPlan(
            moveDate: compressedMoveDate,
            generatedAt: compressed.generatedAt,
            reflowedAt: nil,
            sessions: compressed.sessions.map { replacing($0, scheduledDate: staleDate) }
        )
        let compressedReflow = PackingPlanEngine.reflowIfNeeded(compressed, today: today, calendar: calendar)
        check(compressedReflow.sessions.first?.isBehindPace == true, "compressed reflow flags only the next session behind pace")
        check(compressedReflow.sessions.dropFirst().allSatisfy { !$0.isBehindPace }, "behind-pace marker is not repeated")

        let completedAt = date(2026, 7, 27, calendar: calendar)
        let firstTaskId = ordered.sessions[0].taskId
        let completion = PackingPlanEngine.completion(
            afterCompleting: firstTaskId,
            in: ordered,
            at: completedAt,
            calendar: calendar
        )!
        check(completion.plan.sessions[0].completedAt == completedAt, "completion marks the plan session")
        check(completion.result.consequenceLine.contains("On pace for August 20."), "completion returns the locked on-pace line")
        check(completion.result.nextSessionDate == ordered.sessions[1].scheduledDate, "completion exposes the next scheduled session")

        let regenerated = PackingPlanEngine.generate(
            rooms: rooms,
            moveDate: date(2026, 8, 25, calendar: calendar),
            today: today,
            calendar: calendar,
            preserving: completion.plan
        )
        let completedSourceKeys = Set(completion.plan.sessions[0].sourceKeys)
        let regeneratedMatches = regenerated.sessions.filter {
            completedSourceKeys.isSubset(of: Set($0.sourceKeys))
        }
        check(regeneratedMatches.first?.completedAt == completedAt, "date regeneration preserves completed source keys")

        if failures.isEmpty {
            print("\nPackingPlanEngineTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nPackingPlanEngineTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }

    private static func orderedFixtureRooms() -> [PackingRoomInput] {
        [
            room("Storage", "Holiday decorations"),
            room("Living Room", "Books"),
            room("Guest Room", "Guest linens"),
            room("Garage", "Hand tools"),
            room("Bedroom 2", "Kids clothes"),
            PackingRoomInput(name: "Kitchen", items: [
                PackingPlanItem(name: "Serving platters", cubicFeet: 3),
                PackingPlanItem(name: "Coffee mugs", cubicFeet: 3)
            ]),
            room("Primary Bedroom", "Hanging clothes"),
            room("Bathroom", "Towels")
        ]
    }

    private static func room(_ name: String, _ item: String) -> PackingRoomInput {
        PackingRoomInput(name: name, items: [PackingPlanItem(name: item, cubicFeet: 3)])
    }

    private static func index(ofPrefix prefix: String, in values: [String]) -> Int {
        values.firstIndex(where: { $0.hasPrefix(prefix) }) ?? Int.max
    }

    private static func replacing(_ session: PackingSession, scheduledDate: Date) -> PackingSession {
        PackingSession(
            taskId: session.taskId,
            sessionKey: session.sessionKey,
            sourceKeys: session.sourceKeys,
            rooms: session.rooms,
            roomLabel: session.roomLabel,
            estMinutes: session.estMinutes,
            scheduledDate: scheduledDate,
            itemSummary: session.itemSummary,
            isFirstNightBag: session.isFirstNightBag,
            completedAt: session.completedAt,
            isBehindPace: session.isBehindPace
        )
    }

    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
