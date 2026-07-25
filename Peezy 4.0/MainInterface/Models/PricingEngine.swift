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

    init(
        cubicFeet: Double,
        driveMinutes: Double,
        originAccess: MoveAccess,
        destAccess: MoveAccess,
        packedStatus: PackedStatus,
        specialtyItems: [SpecialtyItem] = [],
        storageStop: StorageStop? = nil,
        serviceDate: Date? = nil,
        cubeSource: CubeSource
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

    init(
        hourlyByCrew: [Int: Double],
        tripCharge: Double,
        minimumHours: Double,
        weekendSurcharge: Double = 0,
        monthEndSurcharge: Double = 0,
        peakSeasonSurcharge: Double = 0
    ) {
        self.hourlyByCrew = hourlyByCrew
        self.tripCharge = tripCharge
        self.minimumHours = minimumHours
        self.weekendSurcharge = weekendSurcharge
        self.monthEndSurcharge = monthEndSurcharge
        self.peakSeasonSurcharge = peakSeasonSurcharge
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
    let price: Double
}

struct PriceEstimate: Equatable {
    let range: PriceRange
    let typicalHours: Double
    let crew: Int
    let disclosures: [String]
    let why: String
}

enum PricingEngine {
    static func loadHours(for scope: MoveScope, crew: Int) -> Double {
        guard let cubePerHour = PricingConstants.cubicFeetPerCrewHour[crew], cubePerHour > 0 else {
            return 0
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
        return roundedHours(baseHours + accessHours + specialtyHours)
    }

    static func crewQuotes(for scope: MoveScope, rateCard: PricingRateCard) -> [CrewQuote] {
        rateCard.hourlyByCrew.keys.sorted().compactMap { crew in
            guard let hourlyRate = rateCard.hourlyByCrew[crew] else { return nil }
            let load = loadHours(for: scope, crew: crew)
            let total = roundedHours(load + scope.driveMinutes / 60)
            let billable = max(total, rateCard.minimumHours)
            let subtotal = billable * hourlyRate + rateCard.tripCharge
            let totalPrice = roundMoney(subtotal * (1 + surchargeFraction(for: scope.serviceDate, rateCard: rateCard)))
            return CrewQuote(
                crew: crew,
                loadHours: load,
                totalHours: total,
                billableHours: billable,
                price: totalPrice
            )
        }
    }

    static func estimate(scope: MoveScope, rateCard: PricingRateCard) -> PriceEstimate? {
        let quotes = crewQuotes(for: scope, rateCard: rateCard)
        guard let selected = quotes.min(by: { lhs, rhs in
            if lhs.price != rhs.price { return lhs.price < rhs.price }
            if lhs.totalHours != rhs.totalHours { return lhs.totalHours < rhs.totalHours }
            return lhs.crew < rhs.crew
        }) else { return nil }

        let rangeWidth = confidenceRangeWidth(for: scope)
        let range = PriceRange(
            low: roundMoney(selected.price * (1 - rangeWidth)),
            high: roundMoney(selected.price * (1 + rangeWidth))
        )
        return PriceEstimate(
            range: range,
            typicalHours: selected.totalHours,
            crew: selected.crew,
            disclosures: disclosures(for: scope),
            why: why(selected: selected, alternatives: quotes)
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
        var width = scope.cubeSource == .inventoryScan
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
        return result
    }

    private static func why(selected: CrewQuote, alternatives: [CrewQuote]) -> String {
        let fasterAlternative = alternatives
            .filter { $0.crew > selected.crew && $0.price >= selected.price && $0.totalHours < selected.totalHours }
            .sorted { $0.totalHours < $1.totalHours }
            .first

        if let fasterAlternative {
            let savedHours = fasterAlternative.totalHours - selected.totalHours
            return "\(selected.crew) movers is the lowest total; \(fasterAlternative.crew) movers finishes \(formatHours(-savedHours)) sooner but costs more."
        }

        let slowerAlternative = alternatives
            .filter { $0.crew < selected.crew && $0.price > selected.price && $0.totalHours > selected.totalHours }
            .sorted { $0.crew > $1.crew }
            .first
        if let slowerAlternative {
            let savedHours = slowerAlternative.totalHours - selected.totalHours
            return "\(selected.crew) movers finishes \(formatHours(savedHours)) sooner and costs less."
        }

        return "\(selected.crew) movers is the lowest total for this scope."
    }

    private static func roundedHours(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func roundMoney(_ value: Double) -> Double {
        value.rounded()
    }

    private static func formatHours(_ hours: Double) -> String {
        String(format: "%.1fh", abs(hours))
    }
}
