import Foundation

// Standalone executable tests for Peezy's pure man-hour estimate. Run with:
// swiftc PricingConstants.swift PricingEngine.swift Tests/PricingEngineTests.swift -o /tmp/peezy_pricing_tests

@main
struct PricingEngineTests {
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

        let baseline = MoveScope(
            cubicFeet: 600,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        check(
            PricingEngine.estimatedManHours(for: baseline) == 8.9,
            "600 cubic feet selects two movers and estimates 8.9 man-hours"
        )

        let larger = MoveScope(
            cubicFeet: 1_000,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        check(
            PricingEngine.estimatedManHours(for: larger) == 17.4,
            "larger scope selects the first crew that stays under six physical hours"
        )

        let beyondOneDay = MoveScope(
            cubicFeet: 2_000,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        check(
            PricingEngine.estimatedManHours(for: beyondOneDay) == 39,
            "scope beyond the six-hour ceiling still receives a four-person baseline"
        )

        let unpacked = MoveScope(
            cubicFeet: 600,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .unpacked,
            cubeSource: .inventoryScan
        )
        let complexAccess = MoveScope(
            cubicFeet: 600,
            originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: true),
            destAccess: MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false),
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        let specialtyAndStorage = MoveScope(
            cubicFeet: 600,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            specialtyItems: [.piano],
            hasStorageStop: true,
            cubeSource: .inventoryScan
        )
        check(
            PricingEngine.estimatedManHours(for: unpacked)
                > PricingEngine.estimatedManHours(for: baseline),
            "unpacked inventory raises the man-hour estimate"
        )
        check(
            PricingEngine.estimatedManHours(for: complexAccess)
                > PricingEngine.estimatedManHours(for: baseline),
            "stairs, elevator, and long carry raise the man-hour estimate"
        )
        check(
            PricingEngine.estimatedManHours(for: specialtyAndStorage)
                > PricingEngine.estimatedManHours(for: baseline),
            "specialty handling and a storage stop raise the man-hour estimate"
        )

        if failures.isEmpty {
            print("\nPricingEngineTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nPricingEngineTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }
}
