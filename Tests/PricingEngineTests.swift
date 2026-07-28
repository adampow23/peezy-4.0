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
            peakSeasonSurcharge: 0.12,
            specialtyFees: [
                .piano: 100, .safe: 80, .poolTable: 90,
                .oversizedAppliance: 50, .treadmill: 60, .marbleTops: 70
            ]
        )

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
        check(largeEstimate.crew == 3, "larger move selects the smallest crew under six physical hours")
        let tiedPriceRateCard = PricingRateCard(
            hourlyByCrew: [2: 100, 3: 100], tripCharge: 0, minimumHours: 2
        )
        let tiedPriceEstimate = PricingEngine.estimate(scope: minimumScope, rateCard: tiedPriceRateCard)!
        check(tiedPriceEstimate.crew == 2, "price does not override the minimum viable crew")

        let belowCeiling = MoveScope(
            cubicFeet: 796.5, driveMinutes: 240,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        let aboveCeiling = MoveScope(
            cubicFeet: 823.5, driveMinutes: 0,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        check(PricingEngine.loadHours(for: belowCeiling, crew: 2) == 5.9, "ceiling fixture models 5.9 physical hours")
        check(PricingEngine.estimate(scope: belowCeiling, rateCard: rateCard)?.crew == 2, "5.9 physical hours stays at two movers despite long drive")
        check(PricingEngine.loadHours(for: aboveCeiling, crew: 2) == 6.1, "ceiling fixture models 6.1 physical hours")
        check(PricingEngine.estimate(scope: aboveCeiling, rateCard: rateCard)?.crew == 3, "6.1 physical hours adds a mover")
        let justAboveCeiling = MoveScope(
            cubicFeet: 811.35, driveMinutes: 0,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        check(
            PricingEngine.estimate(scope: justAboveCeiling, rateCard: rateCard)?.crew == 3,
            "unrounded 6.01 physical hours adds a mover even when display hours round to 6.0"
        )

        let exactLargestCrewCeiling = MoveScope(
            cubicFeet: 1_230, driveMinutes: 600,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        let aboveLargestCrewCeiling = MoveScope(
            cubicFeet: 1_230.205, driveMinutes: 0,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        check(PricingEngine.physicalHours(for: exactLargestCrewCeiling, crew: 4) == 6,
              "largest crew fixture models exactly 6.0 unrounded physical hours")
        check(
            PricingEngine.quoteRoute(
                scope: exactLargestCrewCeiling,
                largestAvailableCrewSize: 4
            ) == .instantComparison,
            "exactly 6.0 physical hours remains instant regardless of drive time"
        )
        check(
            PricingEngine.quoteRoute(
                scope: aboveLargestCrewCeiling,
                largestAvailableCrewSize: 4
            ) == .conciergeQuote,
            "more than 6.0 physical hours at the largest crew routes concierge"
        )
        check(
            PricingEngine.quoteRoute(
                scope: baseline,
                largestAvailableCrewSize: nil
            ) == .conciergeQuote,
            "no positive active-vendor crew routes concierge"
        )
        check(PricingEngine.estimate(scope: aboveLargestCrewCeiling, rateCard: rateCard) == nil,
              "a vendor card never falls back to an over-ceiling estimate")
        let unavailableFourPersonCard = PricingRateCard(
            hourlyByCrew: [3: 150, 4: 0], tripCharge: 0, minimumHours: 2
        )
        let needsFourPeople = MoveScope(
            cubicFeet: 1_100, driveMinutes: 0,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        check(PricingEngine.estimate(scope: needsFourPeople, rateCard: unavailableFourPersonCard) == nil,
              "a nonpositive rate does not make that crew size available")
        let invariantScopes = [minimumScope, belowCeiling, aboveCeiling, justAboveCeiling]
        for (index, invariantScope) in invariantScopes.enumerated() {
            if let estimate = PricingEngine.estimate(scope: invariantScope, rateCard: rateCard) {
                check(
                    PricingEngine.physicalHours(for: invariantScope, crew: estimate.crew)
                        <= PricingConstants.physicalHoursCeiling,
                    "why-line estimate fixture \(index + 1) never exceeds physical-hours ceiling"
                )
            }
        }

        check(PricingEngine.quoteRoute(moveDistanceMiles: 100) == .instantComparison, "100-mile boundary stays instant")
        check(PricingEngine.quoteRoute(moveDistanceMiles: 100.1) == .conciergeQuote, "over 100 miles routes to concierge")
        check(PricingEngine.quoteRoute(moveDistanceMiles: nil) == .conciergeQuote, "pending distance routes to concierge")

        let pianoFlipBase = MoveScope(
            cubicFeet: 620, driveMinutes: 15,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan
        )
        let pianoFlip = MoveScope(
            cubicFeet: 620, driveMinutes: 15,
            originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, specialtyItems: [.piano], cubeSource: .inventoryScan
        )
        check(PricingEngine.estimate(scope: pianoFlipBase, rateCard: rateCard)?.crew == 2, "base scope stays at two movers")
        check(PricingEngine.loadHours(for: pianoFlip, crew: 2) == 6.1, "piano hours are added before crew selection")
        check(PricingEngine.estimate(scope: pianoFlip, rateCard: rateCard)?.crew == 3, "piano physical hours trigger the extra mover")

        let higherPianoFeeCard = PricingRateCard(
            hourlyByCrew: rateCard.hourlyByCrew,
            tripCharge: rateCard.tripCharge,
            minimumHours: rateCard.minimumHours,
            specialtyFees: [.piano: 250]
        )
        let standardPianoQuote = PricingEngine.crewQuotes(for: pianoFlip, rateCard: rateCard)
            .first { $0.crew == 3 }!
        let higherPianoQuote = PricingEngine.crewQuotes(for: pianoFlip, rateCard: higherPianoFeeCard)
            .first { $0.crew == 3 }!
        check(higherPianoQuote.price - standardPianoQuote.price == 150, "vendor specialty fees create card-price divergence")
        check(
            PricingEngine.estimate(scope: pianoFlip, rateCard: rateCard)?.specialtyHandlingNotes
                == ["Includes piano handling"],
            "priced specialty emits the locked comparison note"
        )

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
        check(
            scannedSameHome.disclosures.contains("Includes what scans can't see — closets, cabinets, drawers."),
            "scan estimate includes the locked hidden-goods disclosure"
        )
        check(
            !fallbackEstimate.disclosures.contains("Includes what scans can't see — closets, cabinets, drawers."),
            "bedrooms fallback does not claim a scan-only hidden-goods adjustment"
        )
        let oneUnseenRoomScope = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan,
            unresolvedUnseenRoomCount: 1
        )
        let manyUnseenRoomsScope = MoveScope(
            cubicFeet: 600, driveMinutes: 0, originAccess: .ground, destAccess: .ground,
            packedStatus: .packed, cubeSource: .inventoryScan,
            unresolvedUnseenRoomCount: 8
        )
        let oneUnseenEstimate = PricingEngine.estimate(scope: oneUnseenRoomScope, rateCard: rateCard)!
        let manyUnseenEstimate = PricingEngine.estimate(scope: manyUnseenRoomsScope, rateCard: rateCard)!
        let resolvedMultipliers = PricingEngine.confidenceRangeMultipliers(for: baseline)
        let oneUnseenMultipliers = PricingEngine.confidenceRangeMultipliers(for: oneUnseenRoomScope)
        let fallbackMultipliers = PricingEngine.confidenceRangeMultipliers(for: fallbackScope)
        check(oneUnseenEstimate.range.low == scannedSameHome.range.low,
              "unresolved room leaves low estimate unchanged")
        check(oneUnseenEstimate.range.high > scannedSameHome.range.high,
              "unresolved room widens high estimate")
        check(oneUnseenMultipliers.high == min(
            resolvedMultipliers.high * (1 + PricingConstants.unresolvedRoomHighSideIncrement),
            fallbackMultipliers.high
        ), "unresolved room applies the locked numeric high-side multiplier")
        check(manyUnseenEstimate.range.high == fallbackEstimate.range.high,
              "unresolved-room widening caps at bedrooms fallback high side")
        check(
            manyUnseenEstimate.range.high - manyUnseenEstimate.range.low
                <= fallbackEstimate.range.high - fallbackEstimate.range.low,
            "unresolved-room total range width never exceeds bedrooms fallback width"
        )
        check(oneUnseenEstimate.disclosures.contains("Some rooms weren't scanned."),
              "unresolved room emits locked disclosure")
        check(!scannedSameHome.disclosures.contains("Some rooms weren't scanned."),
              "resolved coverage omits unresolved-room disclosure")
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

        let calibrationRateCard = PricingRateCard(
            hourlyByCrew: [2: 145, 3: 185, 4: 220],
            tripCharge: 129,
            minimumHours: 2,
            specialtyFees: [.piano: 240]
        )
        let similarityFixtures = [
            MoveScope(cubicFeet: 480, driveMinutes: 18,
                      originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false),
                      destAccess: .ground, packedStatus: .packed, cubeSource: .inventoryScan),
            MoveScope(cubicFeet: 900, driveMinutes: 28,
                      originAccess: MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false),
                      destAccess: .ground, packedStatus: .unpacked, cubeSource: .inventoryScan),
            MoveScope(cubicFeet: 1_420, driveMinutes: 42,
                      originAccess: .ground,
                      destAccess: MoveAccess(route: .elevator, elevatorReserved: true, longCarry: true),
                      packedStatus: .packed, specialtyItems: [.piano], cubeSource: .inventoryScan),
            MoveScope(cubicFeet: 1_275, driveMinutes: 35,
                      originAccess: .defaulted, destAccess: .defaulted,
                      packedStatus: .unknown, cubeSource: .bedroomsFallback)
        ]
        for (fixtureIndex, fixture) in similarityFixtures.enumerated() {
            let prices = PricingEngine.crewQuotes(for: fixture, rateCard: calibrationRateCard).map(\.price)
            check(adjacentPricesAreSimilar(prices), "fixture \(fixtureIndex + 1) adjacent crew totals stay within 10%")
        }

        if failures.isEmpty {
            print("\nPricingEngineTests: PASS (\(checksRun) assertions)")
        } else {
            print("\nPricingEngineTests: FAIL (\(failures.count) failures)")
            exit(1)
        }
    }

    private static func adjacentPricesAreSimilar(_ prices: [Double]) -> Bool {
        zip(prices, prices.dropFirst()).allSatisfy { left, right in
            abs(left - right) / min(left, right) <= 0.10
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
