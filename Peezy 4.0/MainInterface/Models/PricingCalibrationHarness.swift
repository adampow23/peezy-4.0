//
//  PricingCalibrationHarness.swift
//  Peezy 4.0
//
//  DEBUG-only, deterministic five-scenario report for field calibration.
//

import Foundation

#if DEBUG
enum PricingCalibrationHarness {
    static func report() -> String {
        scenarios.enumerated().map { index, scenario in
            if PricingEngine.quoteRoute(moveDistanceMiles: scenario.distanceMiles) == .conciergeQuote {
                return """
                SCENARIO \(index + 1): \(scenario.name)
                  distance: \(Int(scenario.distanceMiles ?? 0)) mi | route: concierge quote request
                  message: Long-distance moves get a hand-built quote from us — you'll have it within a day.
                  hourly pricing: not generated
                """
            }

            let quotes = PricingEngine.crewQuotes(for: scenario.scope, rateCard: scenario.rateCard)
            let estimate = PricingEngine.estimate(scope: scenario.scope, rateCard: scenario.rateCard)!
            let quoteLines = quotes.map {
                let fee = $0.specialtyFee > 0 ? ", specialty fee $\(money($0.specialtyFee))" : ""
                return "  \($0.crew)-crew: load \(hours($0.loadHours)), total \(hours($0.totalHours)), billable \(hours($0.billableHours))\(fee), $\(money($0.price))"
            }.joined(separator: "\n")
            let specialtyLine: String
            if scenario.scope.specialtyItems.isEmpty {
                specialtyLine = ""
            } else {
                let names = scenario.scope.specialtyItems.map(\.handlingLabel).joined(separator: ", ")
                let addedHours = scenario.scope.specialtyItems.reduce(0) {
                    $0 + (PricingConstants.specialtyItemHours[$1] ?? 0)
                }
                specialtyLine = "\n  specialty: \(names) | added physical hours: \(hours(addedHours))"
            }
            return """
            SCENARIO \(index + 1): \(scenario.name)
              scope: \(Int(scenario.scope.cubicFeet)) cu ft | \(Int(scenario.scope.driveMinutes)) min drive | \(scenario.scope.cubeSource.rawValue) | \(scenario.scope.packedStatus.rawValue)\(specialtyLine)
            \(quoteLines)
              selected: \(estimate.crew)-crew, \(hours(estimate.typicalHours)), $\(money(estimate.range.low))–$\(money(estimate.range.high))
              why: \(estimate.why)
              disclosures: \(estimate.disclosures.isEmpty ? "none" : estimate.disclosures.joined(separator: "; "))
            """
        }.joined(separator: "\n\n")
    }

    private static let rateCard = PricingRateCard(
        hourlyByCrew: [2: 145, 3: 185, 4: 220],
        tripCharge: 129,
        minimumHours: 2,
        weekendSurcharge: 0.10,
        monthEndSurcharge: 0.08,
        peakSeasonSurcharge: 0.12,
        specialtyFees: [
            .piano: 240,
            .safe: 175,
            .poolTable: 200,
            .oversizedAppliance: 75,
            .treadmill: 85,
            .marbleTops: 140
        ]
    )

    private static let scenarios: [(name: String, distanceMiles: Double?, scope: MoveScope, rateCard: PricingRateCard)] = [
        (
            "1BR local walkup",
            8,
            MoveScope(cubicFeet: 480, driveMinutes: 18,
                      originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false),
                      destAccess: .ground, packedStatus: .packed,
                      serviceDate: date(2026, 4, 14), cubeSource: .inventoryScan),
            rateCard
        ),
        (
            "2BR local elevator, unreserved",
            12,
            MoveScope(cubicFeet: 900, driveMinutes: 28,
                      originAccess: MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false),
                      destAccess: .ground, packedStatus: .unpacked,
                      serviceDate: date(2026, 6, 27), cubeSource: .inventoryScan),
            rateCard
        ),
        (
            "3BR scan with storage and piano",
            25,
            MoveScope(cubicFeet: 1_420, driveMinutes: 42,
                      originAccess: .ground,
                      destAccess: MoveAccess(route: .elevator, elevatorReserved: true, longCarry: true),
                      packedStatus: .packed, specialtyItems: [.piano],
                      storageStop: StorageStop(size: "Medium", fullness: "1/2"),
                      serviceDate: date(2026, 8, 29), cubeSource: .inventoryScan),
            rateCard
        ),
        (
            "3BR bedrooms fallback, access unknown",
            60,
            MoveScope(cubicFeet: 1_275, driveMinutes: 35,
                      originAccess: .defaulted, destAccess: .defaulted,
                      packedStatus: .unknown,
                      serviceDate: date(2026, 10, 17), cubeSource: .bedroomsFallback),
            rateCard
        ),
        (
            "4BR interstate",
            540,
            MoveScope(cubicFeet: 2_100, driveMinutes: 540,
                      originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: true),
                      destAccess: .ground, packedStatus: .packed,
                      specialtyItems: [.safe, .oversizedAppliance],
                      serviceDate: date(2026, 7, 25), cubeSource: .inventoryScan),
            rateCard
        )
    ]

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private static func hours(_ value: Double) -> String {
        String(format: "%.1fh", value)
    }

    private static func money(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
#endif
