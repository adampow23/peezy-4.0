//
//  PricingEngine.swift
//  Peezy 4.0
//
//  Pure moving-labor domain: no Firebase, networking, UI, vendor rates, or
//  dollar estimates. The only public estimate is Peezy's man-hour baseline.
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
}

struct StorageContents: Equatable {
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
        if longCarry {
            hours += PricingConstants.longCarryHoursPerLocation
        }
        return hours
    }
}

struct MoveScope: Equatable {
    let cubicFeet: Double
    let originAccess: MoveAccess
    let destAccess: MoveAccess
    let packedStatus: PackedStatus
    let specialtyItems: [SpecialtyItem]
    let storageContents: StorageContents?
    let hasStorageStop: Bool
    let cubeSource: CubeSource

    init(
        cubicFeet: Double,
        originAccess: MoveAccess,
        destAccess: MoveAccess,
        packedStatus: PackedStatus,
        specialtyItems: [SpecialtyItem] = [],
        storageContents: StorageContents? = nil,
        hasStorageStop: Bool = false,
        cubeSource: CubeSource
    ) {
        self.cubicFeet = max(cubicFeet, 0)
        self.originAccess = originAccess
        self.destAccess = destAccess
        self.packedStatus = packedStatus
        self.specialtyItems = specialtyItems
        self.storageContents = storageContents
        self.hasStorageStop = hasStorageStop
        self.cubeSource = cubeSource
    }
}

enum PricingEngine {
    /// Peezy's time basis in crew-independent man-hours. Crew selection keeps
    /// the existing one-day ceiling; scopes beyond it use the largest modeled
    /// crew instead of suppressing the estimate.
    static func estimatedManHours(for scope: MoveScope) -> Double {
        let crewSizes = PricingConstants.cubicFeetPerCrewHour.keys.sorted()
        guard let largestCrew = crewSizes.last else { return 0 }
        let crew = crewSizes.first {
            physicalHours(for: scope, crew: $0) <= PricingConstants.physicalHoursCeiling
        } ?? largestCrew
        return roundedHours(physicalHours(for: scope, crew: crew) * Double(crew))
    }

    static func loadHours(for scope: MoveScope, crew: Int) -> Double {
        roundedHours(physicalHours(for: scope, crew: crew))
    }

    /// Unrounded modeled loading/unloading work. Travel is intentionally not
    /// included because every entered quote carries its own trip/travel fee.
    static func physicalHours(for scope: MoveScope, crew: Int) -> Double {
        guard let cubePerHour = PricingConstants.cubicFeetPerCrewHour[crew], cubePerHour > 0 else {
            return .infinity
        }

        let packingMultiplier: Double
        switch scope.packedStatus {
        case .packed:
            packingMultiplier = 1
        case .unpacked:
            packingMultiplier = PricingConstants.unpackedBoxesMultiplier
        case .unknown:
            packingMultiplier = PricingConstants.unknownPackingMultiplier
        }

        let baseHours = (scope.cubicFeet / cubePerHour) * packingMultiplier
        let accessHours = scope.originAccess.laborHours + scope.destAccess.laborHours
        let specialtyHours = scope.specialtyItems.reduce(0) {
            $0 + (PricingConstants.specialtyItemHours[$1] ?? 0)
        }
        let storageStopHours = scope.hasStorageStop
            ? PricingConstants.storageStopLoadHours
            : 0
        return baseHours + accessHours + specialtyHours + storageStopHours
    }

    private static func roundedHours(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
