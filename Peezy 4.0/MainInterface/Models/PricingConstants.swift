//
//  PricingConstants.swift
//  Peezy 4.0
//
//  One review surface for the mover estimate. All values in this file are
//  intentionally labelled LOCKED-pending-calibration: Adam's field estimates
//  are the authority before rate cards are offered to real customers.
//

import Foundation

enum PricingConstants {
    // MARK: Scope constants

    /// LOCKED-pending-calibration item-to-cubic-feet table. Item names from the
    /// scan are normalized and matched by containment, with scanner cube data as
    /// a fallback only for an unrecognized name.
    static let lockedItemCubicFeet: [String: Double] = [
        "sectional": 110,
        "sofa": 65,
        "loveseat": 45,
        "recliner": 35,
        "armchair": 25,
        "bed frame": 45,
        "king mattress": 35,
        "queen mattress": 30,
        "full mattress": 25,
        "twin mattress": 18,
        "dresser": 35,
        "wardrobe": 45,
        "dining table": 45,
        "coffee table": 20,
        "desk": 30,
        "bookcase": 30,
        "tv stand": 25,
        "television": 12,
        "washer": 30,
        "dryer": 30,
        "refrigerator": 55,
        "piano": 75,
        "safe": 20,
        "box": 4
    ]

    /// Used only when a scanned item has no named table match and no scanner
    /// cube estimate. LOCKED-pending-calibration.
    static let unclassifiedItemCubicFeet: Double = 12

    /// LOCKED-pending-calibration no-video fallback. The midpoint is used for
    /// the estimate and the wide source flag widens the customer-facing range.
    static let bedroomFallbackCubicFeet: [Int: ClosedRange<Double>] = [
        1: 350...650,
        2: 650...1_050,
        3: 1_000...1_550,
        4: 1_450...2_250,
        5: 2_000...3_000,
        6: 2_600...3_800
    ]

    /// LOCKED-pending-calibration allowance for goods a room scan cannot see.
    /// The bedroom fallback ranges above already include hidden goods, so this
    /// table is applied only when inventoryScan is the cube source.
    static let hiddenGoodsCubeByBedrooms: [Int: Double] = [
        1: 80,
        2: 140,
        3: 220,
        4: 300
    ]

    /// LOCKED-pending-calibration storage contribution from the Spec 02 trio.
    static let storageUnitCubicFeet: [String: Double] = [
        "small": 180,
        "medium": 420,
        "large": 780
    ]

    static let storageFullnessMultiplier: [String: Double] = [
        "1/4": 0.25,
        "1/2": 0.50,
        "3/4": 0.75,
        "full": 1.00
    ]

    /// Only used when MapKit cannot return an ETA because one or both identity
    /// addresses are absent or not geocodable. LOCKED-pending-calibration.
    static let defaultDriveMinutes: Double = 30

    // MARK: Labor constants

    /// LOCKED-pending-calibration cubic feet handled per crew hour.
    static let cubicFeetPerCrewHour: [Int: Double] = [
        2: 135,
        3: 172,
        4: 205
    ]

    /// A crew is increased only when modeled physical work exceeds this
    /// ceiling. Drive time is deliberately excluded from the decision.
    static let physicalHoursCeiling: Double = 6

    /// LOCKED-pending-calibration labor multipliers and additions.
    static let unpackedBoxesMultiplier: Double = 1.20
    static let unknownPackingMultiplier: Double = 1.10
    static let stairsHoursPerLocation: Double = 0.55
    static let elevatorUnreservedHoursPerLocation: Double = 0.30
    static let elevatorReservedHoursPerLocation: Double = 0.10
    static let longCarryHoursPerLocation: Double = 0.50
    static let specialtyItemHours: [SpecialtyItem: Double] = [
        .piano: 1.50,
        .safe: 1.25,
        .poolTable: 1.25,
        .oversizedAppliance: 0.50,
        .treadmill: 0.75,
        .marbleTops: 1.00
    ]

    // MARK: Confidence constants

    /// These widths are half-widths, expressed as a fraction of the modeled
    /// price. They make a bedrooms-only scope materially wider than a scan.
    static let scannedInventoryRangeWidth: Double = 0.12
    static let bedroomsFallbackRangeWidth: Double = 0.28
    static let defaultAccessRangeWidthIncrement: Double = 0.10
    static let unknownPackingRangeWidthIncrement: Double = 0.04
    /// Multiplies the scan estimate's high-side range for each unresolved
    /// expected room. LOCKED-pending-calibration.
    static let unresolvedRoomHighSideIncrement: Double = 0.15

    static func cubicFeet(
        forItemNamed name: String,
        scannerEstimate: Double,
        quantity: Int
    ) -> Double {
        let normalizedName = name.lowercased()
        let matchedCube = lockedItemCubicFeet
            .sorted { $0.key.count > $1.key.count }
            .first(where: { normalizedName.contains($0.key) })?
            .value
        let perItem = matchedCube ?? (scannerEstimate > 0 ? scannerEstimate : unclassifiedItemCubicFeet)
        return perItem * Double(max(quantity, 1))
    }

    static func bedroomCubeRange(for bedroomsAnswer: String) -> ClosedRange<Double> {
        let firstNumber = bedroomsAnswer.split(whereSeparator: { !$0.isNumber }).first
            .flatMap { Int($0) }
        let cappedBedrooms = min(max(firstNumber ?? 1, 1), 6)
        return bedroomFallbackCubicFeet[cappedBedrooms] ?? bedroomFallbackCubicFeet[1]!
    }

    static func hiddenGoodsCubeFeet(for bedroomsAnswer: String) -> Double {
        let firstNumber = bedroomsAnswer.split(whereSeparator: { !$0.isNumber }).first
            .flatMap { Int($0) }
        let cappedBedrooms = min(max(firstNumber ?? 1, 1), 4)
        return hiddenGoodsCubeByBedrooms[cappedBedrooms] ?? hiddenGoodsCubeByBedrooms[1]!
    }

    static func storageCubeFeet(size: String, fullness: String) -> Double {
        let unitCube = storageUnitCubicFeet[size.lowercased()] ?? 0
        let multiplier = storageFullnessMultiplier[fullness.lowercased()] ?? 0
        return unitCube * multiplier
    }
}
