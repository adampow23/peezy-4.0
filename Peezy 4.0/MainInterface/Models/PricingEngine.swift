//
//  PricingEngine.swift
//  Peezy 4.0
//
//  Pure pricing domain: no Firebase, networking, UI, or persistence. This is
//  deliberately standalone so the executable tests in /Tests can compile it.
//

import Foundation

enum CubeSource: String, Equatable {
    case inventoryScan
    case bedroomsFallback
}

enum PackedStatus: String, Equatable {
    case packed
    case unpacked
    case unknown
}

enum SpecialtyItem: String, CaseIterable, Equatable {
    case piano
    case safe
    case poolTable
    case oversizedAppliance
    case treadmill
    case marbleTops

    var handlingLabel: String {
        switch self {
        case .piano: "piano"
        case .safe: "safe"
        case .poolTable: "pool table"
        case .oversizedAppliance: "oversized appliance"
        case .treadmill: "treadmill"
        case .marbleTops: "marble tops"
        }
    }
}

enum MoverQuoteRoute: Equatable {
    case instantComparison
    case conciergeQuote
}

struct StorageStop: Equatable {
    let size: String
    let fullness: String

    var addedCubicFeet: Double {
        PricingConstants.storageCubeFeet(size: size, fullness: fullness)
    }
}

struct MoveAccess: Equatable {
    enum Route: String, Equatable {
        case ground
        case stairs
        case elevator
        case unknown
    }

    let route: Route
    let elevatorReserved: Bool
    let longCarry: Bool

    static let defaulted = MoveAccess(route: .unknown, elevatorReserved: false, longCarry: false)
    static let ground = MoveAccess(route: .ground, elevatorReserved: false, longCarry: false)

    var isDefaulted: Bool { route == .unknown }

    var laborHours: Double {
        var hours: Double
        switch route {
        case .ground, .unknown:
            hours = 0
        case .stairs:
            hours = PricingConstants.stairsHoursPerLocation
        case .elevator:
            hours = elevatorReserved
                ? PricingConstants.elevatorReservedHoursPerLocation
                : PricingConstants.elevatorUnreservedHoursPerLocation
        }
        if longCarry { hours += PricingConstants.longCarryHoursPerLocation }
        return hours
    }
}

struct MoveScope: Equatable {
    let cubicFeet: Double
    let driveMinutes: Double
    let originAccess: MoveAccess
    let destAccess: MoveAccess
    let packedStatus: PackedStatus
    let specialtyItems: [SpecialtyItem]
    let storageStop: StorageStop?
    let serviceDate: Date?
    let cubeSource: CubeSource
    let unresolvedUnseenRoomCount: Int

    init(
        cubicFeet: Double,
        driveMinutes: Double,
        originAccess: MoveAccess,
        destAccess: MoveAccess,
        packedStatus: PackedStatus,
        specialtyItems: [SpecialtyItem] = [],
        storageStop: StorageStop? = nil,
        serviceDate: Date? = nil,
        cubeSource: CubeSource,
        unresolvedUnseenRoomCount: Int = 0
    ) {
        self.cubicFeet = max(cubicFeet, 0)
        self.driveMinutes = max(driveMinutes, 0)
        self.originAccess = originAccess
        self.destAccess = destAccess
        self.packedStatus = packedStatus
        self.specialtyItems = specialtyItems
        self.storageStop = storageStop
        self.serviceDate = serviceDate
        self.cubeSource = cubeSource
        self.unresolvedUnseenRoomCount = max(unresolvedUnseenRoomCount, 0)
    }
}

/// Transport-neutral representation of a vendor rate card. Phase C adapts the
/// Firestore-decoded VendorRateCard into this pure value before estimating.
struct PricingRateCard: Equatable {
    let hourlyByCrew: [Int: Double]
    let tripCharge: Double
    let minimumHours: Double
    let weekendSurcharge: Double
    let monthEndSurcharge: Double
    let peakSeasonSurcharge: Double
    let specialtyFees: [SpecialtyItem: Double]

    init(
        hourlyByCrew: [Int: Double],
        tripCharge: Double,
        minimumHours: Double,
        weekendSurcharge: Double = 0,
        monthEndSurcharge: Double = 0,
        peakSeasonSurcharge: Double = 0,
        specialtyFees: [SpecialtyItem: Double] = [:]
    ) {
        self.hourlyByCrew = hourlyByCrew
        self.tripCharge = tripCharge
        self.minimumHours = minimumHours
        self.weekendSurcharge = weekendSurcharge
        self.monthEndSurcharge = monthEndSurcharge
        self.peakSeasonSurcharge = peakSeasonSurcharge
        self.specialtyFees = specialtyFees
    }
}

struct PriceRange: Equatable {
    let low: Double
    let high: Double
}

struct CrewQuote: Equatable {
    let crew: Int
    let loadHours: Double
    let totalHours: Double
    let billableHours: Double
    let specialtyFee: Double
    let price: Double
}

struct PriceEstimate: Equatable {
    let range: PriceRange
    let typicalHours: Double
    let crew: Int
    let disclosures: [String]
    let why: String
    let specialtyHandlingNotes: [String]

    init(
        range: PriceRange,
        typicalHours: Double,
        crew: Int,
        disclosures: [String],
        why: String,
        specialtyHandlingNotes: [String] = []
    ) {
        self.range = range
        self.typicalHours = typicalHours
        self.crew = crew
        self.disclosures = disclosures
        self.why = why
        self.specialtyHandlingNotes = specialtyHandlingNotes
    }
}

enum PricingEngine {
    static func quoteRoute(moveDistanceMiles: Double?) -> MoverQuoteRoute {
        guard let moveDistanceMiles, moveDistanceMiles <= 100 else {
            return .conciergeQuote
        }
        return .instantComparison
    }

    /// Local-move size gate. The caller supplies the single largest positive-
    /// rate crew size found across active vendors; vendor-by-vendor gating is
    /// intentionally unnecessary. Physical work is unrounded and excludes drive.
    static func quoteRoute(
        scope: MoveScope,
        largestAvailableCrewSize: Int?
    ) -> MoverQuoteRoute {
        guard let crew = largestAvailableCrewSize else { return .conciergeQuote }
        let hours = physicalHours(for: scope, crew: crew)
        return hours.isFinite && hours <= PricingConstants.physicalHoursCeiling
            ? .instantComparison
            : .conciergeQuote
    }

    static func loadHours(for scope: MoveScope, crew: Int) -> Double {
        roundedHours(physicalHours(for: scope, crew: crew))
    }

    /// Unrounded modeled loading/unloading work used for every ceiling decision.
    /// Invalid crew sizes return infinity so they can never pass a safety gate.
    static func physicalHours(for scope: MoveScope, crew: Int) -> Double {
        guard let cubePerHour = PricingConstants.cubicFeetPerCrewHour[crew], cubePerHour > 0 else {
            return .infinity
        }

        let packingMultiplier: Double
        switch scope.packedStatus {
        case .packed: packingMultiplier = 1
        case .unpacked: packingMultiplier = PricingConstants.unpackedBoxesMultiplier
        case .unknown: packingMultiplier = PricingConstants.unknownPackingMultiplier
        }

        let baseHours = (scope.cubicFeet / cubePerHour) * packingMultiplier
        let accessHours = scope.originAccess.laborHours + scope.destAccess.laborHours
        let specialtyHours = scope.specialtyItems.reduce(0) {
            $0 + (PricingConstants.specialtyItemHours[$1] ?? 0)
        }
        return baseHours + accessHours + specialtyHours
    }

    static func crewQuotes(for scope: MoveScope, rateCard: PricingRateCard) -> [CrewQuote] {
        rateCard.hourlyByCrew.keys.sorted().compactMap { crew in
            guard let hourlyRate = rateCard.hourlyByCrew[crew], hourlyRate > 0,
                  PricingConstants.cubicFeetPerCrewHour[crew] != nil
            else { return nil }
            let load = loadHours(for: scope, crew: crew)
            let total = roundedHours(load + scope.driveMinutes / 60)
            let billable = max(total, rateCard.minimumHours)
            let subtotal = billable * hourlyRate + rateCard.tripCharge
            let specialtyFee = scope.specialtyItems.reduce(0) {
                $0 + (rateCard.specialtyFees[$1] ?? 0)
            }
            let totalPrice = roundMoney(
                subtotal * (1 + surchargeFraction(for: scope.serviceDate, rateCard: rateCard))
                    + specialtyFee
            )
            return CrewQuote(
                crew: crew,
                loadHours: load,
                totalHours: total,
                billableHours: billable,
                specialtyFee: specialtyFee,
                price: totalPrice
            )
        }
    }

    static func estimate(scope: MoveScope, rateCard: PricingRateCard) -> PriceEstimate? {
        let quotes = crewQuotes(for: scope, rateCard: rateCard)
        // Request the minimum viable crew every company can staff. Vendors
        // cannot be forced into larger crews, so selection starts at two and
        // increases only when physical load/unload work exceeds six hours.
        guard let selected = quotes.first(where: {
            physicalHours(for: scope, crew: $0.crew) <= PricingConstants.physicalHoursCeiling
        }) else { return nil }

        let multipliers = confidenceRangeMultipliers(for: scope)
        let range = PriceRange(
            low: roundMoney(selected.price * multipliers.low),
            high: roundMoney(selected.price * multipliers.high)
        )
        return PriceEstimate(
            range: range,
            typicalHours: selected.totalHours,
            crew: selected.crew,
            disclosures: disclosures(for: scope),
            why: "Sized so your move wraps in one solid morning — not a marathon.",
            specialtyHandlingNotes: specialtyHandlingNotes(for: scope, rateCard: rateCard)
        )
    }

    static func surchargeFraction(for serviceDate: Date?, rateCard: PricingRateCard) -> Double {
        guard let serviceDate else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.weekday, .day, .month], from: serviceDate)
        var surcharge: Double = 0
        if let weekday = components.weekday, weekday == 1 || weekday == 7 {
            surcharge += rateCard.weekendSurcharge
        }
        if let day = components.day, day >= 25 {
            surcharge += rateCard.monthEndSurcharge
        }
        if let month = components.month, (5...9).contains(month) {
            surcharge += rateCard.peakSeasonSurcharge
        }
        return surcharge
    }

    static func confidenceRangeWidth(for scope: MoveScope) -> Double {
        confidenceRangeWidth(for: scope.cubeSource, scope: scope)
    }

    static func confidenceRangeMultipliers(for scope: MoveScope) -> (low: Double, high: Double) {
        let width = confidenceRangeWidth(for: scope)
        let baseHigh = 1 + width
        guard scope.cubeSource == .inventoryScan,
              scope.unresolvedUnseenRoomCount > 0
        else { return (1 - width, baseHigh) }

        let unresolvedMultiplier = 1 + (
            PricingConstants.unresolvedRoomHighSideIncrement
                * Double(scope.unresolvedUnseenRoomCount)
        )
        let fallbackCap = 1 + confidenceRangeWidth(for: .bedroomsFallback, scope: scope)
        return (1 - width, min(baseHigh * unresolvedMultiplier, fallbackCap))
    }

    private static func confidenceRangeWidth(for source: CubeSource, scope: MoveScope) -> Double {
        var width = source == .inventoryScan
            ? PricingConstants.scannedInventoryRangeWidth
            : PricingConstants.bedroomsFallbackRangeWidth
        if scope.originAccess.isDefaulted || scope.destAccess.isDefaulted {
            width += PricingConstants.defaultAccessRangeWidthIncrement
        }
        if scope.packedStatus == .unknown {
            width += PricingConstants.unknownPackingRangeWidthIncrement
        }
        return width
    }

    static func disclosures(for scope: MoveScope) -> [String] {
        var result: [String] = []
        if scope.cubeSource == .inventoryScan {
            result.append("Includes what scans can't see — closets, cabinets, drawers.")
        }
        if scope.packedStatus == .unpacked { result.append("Unpacked boxes") }
        if scope.originAccess.route == .elevator && !scope.originAccess.elevatorReserved {
            result.append("Unreserved elevator at origin")
        }
        if scope.destAccess.route == .elevator && !scope.destAccess.elevatorReserved {
            result.append("Unreserved elevator at destination")
        }
        if scope.originAccess.longCarry { result.append("Long carry at origin") }
        if scope.destAccess.longCarry { result.append("Long carry at destination") }
        if scope.originAccess.isDefaulted || scope.destAccess.isDefaulted {
            result.append("Undisclosed stairs or access")
        }
        if scope.cubeSource == .inventoryScan && scope.unresolvedUnseenRoomCount > 0 {
            result.append("Some rooms weren't scanned.")
        }
        return result
    }

    private static func specialtyHandlingNotes(
        for scope: MoveScope,
        rateCard: PricingRateCard
    ) -> [String] {
        var seen: Set<String> = []
        return scope.specialtyItems.compactMap { item in
            guard (rateCard.specialtyFees[item] ?? 0) > 0,
                  seen.insert(item.rawValue).inserted
            else { return nil }
            return "Includes \(item.handlingLabel) handling"
        }
    }

    private static func roundedHours(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func roundMoney(_ value: Double) -> Double {
        value.rounded()
    }

}
