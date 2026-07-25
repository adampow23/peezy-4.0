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
            let quotes = PricingEngine.crewQuotes(for: scenario.scope, rateCard: scenario.rateCard)
            let estimate = PricingEngine.estimate(scope: scenario.scope, rateCard: scenario.rateCard)!
            let quoteLines = quotes.map {
                "  \($0.crew)-crew: load \(hours($0.loadHours)), total \(hours($0.totalHours)), billable \(hours($0.billableHours)), $\(money($0.price))"
            }.joined(separator: "\n")
            return """
            SCENARIO \(index + 1): \(scenario.name)
              scope: \(Int(scenario.scope.cubicFeet)) cu ft | \(Int(scenario.scope.driveMinutes)) min drive | \(scenario.scope.cubeSource.rawValue) | \(scenario.scope.packedStatus.rawValue)
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
        peakSeasonSurcharge: 0.12
    )

    private static let scenarios: [(name: String, scope: MoveScope, rateCard: PricingRateCard)] = [
        (
            "1BR local walkup",
            MoveScope(cubicFeet: 480, driveMinutes: 18,
                      originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false),
                      destAccess: .ground, packedStatus: .packed,
                      serviceDate: date(2026, 4, 14), cubeSource: .inventoryScan),
            rateCard
        ),
        (
            "2BR local elevator, unreserved",
            MoveScope(cubicFeet: 900, driveMinutes: 28,
                      originAccess: MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false),
                      destAccess: .ground, packedStatus: .unpacked,
                      serviceDate: date(2026, 6, 27), cubeSource: .inventoryScan),
            rateCard
        ),
        (
            "3BR scan with storage and piano",
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
            MoveScope(cubicFeet: 1_275, driveMinutes: 35,
                      originAccess: .defaulted, destAccess: .defaulted,
                      packedStatus: .unknown,
                      serviceDate: date(2026, 10, 17), cubeSource: .bedroomsFallback),
            rateCard
        ),
        (
            "4BR interstate",
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
