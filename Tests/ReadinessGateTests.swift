import Foundation

@main
struct ReadinessGateTests {
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

        var checklist = ReadinessChecklist(
            allSessionsComplete: true,
            accessReserved: true
        )
        check(checklist[.allSessionsComplete], "packing completion can prefill")
        check(checklist[.accessReserved], "reserve-access answers can prefill")
        check(!checklist.isComplete, "partial prefill does not complete the gate")

        checklist[.furnitureDisassembled] = true
        checklist[.pathClear] = true
        checklist[.firstNightBagSetAside] = true
        check(checklist.isComplete, "all five items complete the gate")
        check(ReadinessChecklist(items: checklist.items) == checklist, "item map round-trips")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tMinusOne = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let lateTMinusOne = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 23, minute: 59))!
        let moveDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        var incomplete = checklist
        incomplete[.pathClear] = false
        check(
            !incomplete.showsIncompleteConsequence(
                scheduledDate: tMinusOne,
                now: lateTMinusOne,
                calendar: calendar
            ),
            "warning stays hidden during T-1"
        )
        check(
            incomplete.showsIncompleteConsequence(
                scheduledDate: tMinusOne,
                now: moveDay,
                calendar: calendar
            ),
            "warning appears after T-1 ends"
        )
        check(
            !checklist.showsIncompleteConsequence(
                scheduledDate: tMinusOne,
                now: moveDay,
                calendar: calendar
            ),
            "complete gate never warns"
        )

        if failures.isEmpty {
            print("\nReadinessGateTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nReadinessGateTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }
}
