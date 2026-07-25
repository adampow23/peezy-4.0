import Foundation

// Standalone executable tests for the pure pricing engine. Run with:
// swiftc -D DEBUG PricingConstants.swift PricingEngine.swift Tests/PricingEngineTests.swift -o /tmp/peezy_pricing_tests && /tmp/peezy_pricing_tests

@main
struct PricingEngineTests {
    static func main() {
        let rateCard = PricingRateCard(
            hourlyByCrew: [2: 100, 3: 150, 4: 210],
            tripCharge: 50,
            minimumHours: 2,
            weekendSurcharge: 0.10,
            monthEndSurcharge: 0.08,
            peakSeasonSurcharge: 0.12
        )

        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                print("PASS  \(name)")
            } else {
                failures.append(name)
                print("FAIL  \(name)")
            }
        }

        let baseline = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        let stairs = MoveScope(
            cubicFeet: 600, driveMinutes: 0,
            originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false),
            destAccess: .ground, packedStatus: .packed, cubeSource: .inventoryScan
        )
        let unpacked = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .unpacked, cubeSource: .inventoryScan
        )
        let unknownPacking = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .unknown, cubeSource: .inventoryScan
        )
        let elevator = MoveScope(
            cubicFeet: 600, driveMinutes: 0,
            originAccess: MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false),
            destAccess: .ground, packedStatus: .packed, cubeSource: .inventoryScan
        )
        let reservedElevator = MoveScope(
            cubicFeet: 600, driveMinutes: 0,
            originAccess: MoveAccess(route: .elevator, elevatorReserved: true, longCarry: false),
            destAccess: .ground, packedStatus: .packed, cubeSource: .inventoryScan
        )
        let longCarry = MoveScope(
            cubicFeet: 600, driveMinutes: 0,
            originAccess: MoveAccess(route: .ground, elevatorReserved: false, longCarry: true),
            destAccess: .ground, packedStatus: .packed, cubeSource: .inventoryScan
        )
        let driveTime = MoveScope(
            cubicFeet: 600, driveMinutes: 60, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )

        check(PricingEngine.loadHours(for: stairs, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2), "stairs modifier increases load hours")
        check(PricingEngine.loadHours(for: unpacked, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2), "unpacked modifier increases load hours")
        check(PricingEngine.loadHours(for: unknownPacking, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2), "unknown-packing modifier increases load hours")
        check(PricingEngine.loadHours(for: elevator, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2), "unreserved elevator modifier increases load hours")
        check(PricingEngine.loadHours(for: reservedElevator, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2), "reserved-elevator modifier increases load hours")
        check(PricingEngine.loadHours(for: elevator, crew: 2) > PricingEngine.loadHours(for: reservedElevator, crew: 2), "unreserved elevator costs more labor than reserved")
        check(PricingEngine.loadHours(for: longCarry, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2), "long-carry modifier increases load hours")
        for specialtyItem in SpecialtyItem.allCases {
            let specialty = MoveScope(
                cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
                packedStatus: .packed, specialtyItems: [specialtyItem], cubeSource: .inventoryScan
            )
            check(
                PricingEngine.loadHours(for: specialty, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2),
                "\(specialtyItem.rawValue) modifier increases load hours"
            )
        }
        check(
            PricingEngine.crewQuotes(for: driveTime, rateCard: rateCard).first { $0.crew == 2 }!.totalHours
                > PricingEngine.crewQuotes(for: baseline, rateCard: rateCard).first { $0.crew == 2 }!.totalHours,
            "drive-time modifier increases total hours"
        )

        let minimumScope = MoveScope(
            cubicFeet: 40, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        let minimumQuote = PricingEngine.crewQuotes(for: minimumScope, rateCard: rateCard).first { $0.crew == 2 }!
        check(minimumQuote.billableHours == 2, "minimum-hours floor is respected")
        check(minimumQuote.price == 250, "minimum-hours floor is included in price")

        let smallEstimate = PricingEngine.estimate(scope: minimumScope, rateCard: rateCard)!
        let largeScope = MoveScope(
            cubicFeet: 1_000, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        let largeEstimate = PricingEngine.estimate(scope: largeScope, rateCard: rateCard)!
        check(smallEstimate.crew == 2, "small move selects two-person crew")
        check(largeEstimate.crew == 3, "larger move flips to three-person crew when lower total")
        let tiedPriceRateCard = PricingRateCard(
            hourlyByCrew: [2: 100, 3: 100], tripCharge: 0, minimumHours: 2
        )
        let tiedPriceEstimate = PricingEngine.estimate(scope: minimumScope, rateCard: tiedPriceRateCard)!
        check(tiedPriceEstimate.crew == 3, "price tie selects the crew with fewer total hours")

        let fallbackScope = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .bedroomsFallback
        )
        let scannedWidth = smallEstimate.range.high - smallEstimate.range.low
        let fallbackEstimate = PricingEngine.estimate(scope: fallbackScope, rateCard: rateCard)!
        let scannedSameHome = PricingEngine.estimate(scope: baseline, rateCard: rateCard)!
        let fallbackWidth = fallbackEstimate.range.high - fallbackEstimate.range.low
        check(fallbackWidth > (scannedSameHome.range.high - scannedSameHome.range.low), "bedrooms fallback produces a wider range than scan scope")
        check(scannedWidth > 0, "price range has a positive width")
        let storageStop = StorageStop(size: "Medium", fullness: "1/2")
        check(storageStop.addedCubicFeet == 210, "storage size and fullness contribute cube")
        let storageScope = MoveScope(
            cubicFeet: baseline.cubicFeet + storageStop.addedCubicFeet,
            driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, storageStop: storageStop, cubeSource: .inventoryScan
        )
        check(
            PricingEngine.loadHours(for: storageScope, crew: 2) > PricingEngine.loadHours(for: baseline, crew: 2),
            "storage contribution increases modeled labor"
        )
        let defaultAccessScope = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .defaulted, destAccess: .defaulted,
            packedStatus: .unknown, cubeSource: .inventoryScan
        )
        let defaultAccessEstimate = PricingEngine.estimate(scope: defaultAccessScope, rateCard: rateCard)!
        check(
            defaultAccessEstimate.range.high - defaultAccessEstimate.range.low
                > scannedSameHome.range.high - scannedSameHome.range.low,
            "default access and unknown packing widen the range"
        )
        check(
            defaultAccessEstimate.disclosures.contains("Undisclosed stairs or access"),
            "default access emits the locked disclosure"
        )

        let julyWeekendMonthEnd = date(2026, 7, 25)
        let surcharge = PricingEngine.surchargeFraction(
            for: julyWeekendMonthEnd,
            rateCard: rateCard
        )
        check(surcharge == 0.30, "weekend, month-end, and peak-season surcharges combine")

        if failures.isEmpty {
            print("\nPricingEngineTests: PASS (24 assertions)")
        } else {
            print("\nPricingEngineTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
