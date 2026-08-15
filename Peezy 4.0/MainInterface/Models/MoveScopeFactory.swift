//
//  MoveScopeFactory.swift
//  Peezy 4.0
//
//  Narrow adapter from submitted inventory plus existing assessment facts to
//  the pure scope consumed by Peezy's man-hour estimator.
//

import Foundation

enum MoveScopeFactory {
    struct CubeResult: Equatable {
        let cubicFeet: Double
        let source: CubeSource
    }

    static func cubeResult(
        inventoryItems: [InventoryItem],
        bedroomsAnswer: String,
        storageContents: StorageContents?
    ) -> CubeResult {
        let storageCube = storageContents?.addedCubicFeet ?? 0
        let includedItems = inventoryItems.filter(\.shouldMove)
        guard !includedItems.isEmpty else {
            let range = PricingConstants.bedroomCubeRange(for: bedroomsAnswer)
            return CubeResult(
                cubicFeet: ((range.lowerBound + range.upperBound) / 2) + storageCube,
                source: .bedroomsFallback
            )
        }

        let inventoryCube = includedItems.reduce(0) { partial, item in
            partial + PricingConstants.cubicFeet(
                forItemNamed: item.name,
                scannerEstimate: item.cubicFeet,
                quantity: item.quantity
            )
        }
        let hiddenGoodsCube = PricingConstants.hiddenGoodsCubeFeet(for: bedroomsAnswer)
        return CubeResult(
            cubicFeet: inventoryCube + hiddenGoodsCube + storageCube,
            source: .inventoryScan
        )
    }

    static func storageContents(from assessment: [String: Any]) -> StorageContents? {
        guard (assessment["hasStorage"] as? String)?.lowercased() == "yes",
              let size = assessment["storageSize"] as? String,
              let fullness = assessment["storageFullness"] as? String,
              !size.isEmpty,
              !fullness.isEmpty
        else { return nil }
        return StorageContents(size: size, fullness: fullness)
    }

    static func access(
        from assessmentAnswer: String?,
        reservationAnswer: String? = nil
    ) -> MoveAccess {
        let normalizedReservation = reservationAnswer?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalizedReservation {
        case "reserved elevator", "reserved":
            return MoveAccess(route: .elevator, elevatorReserved: true, longCarry: false)
        case "elevator", "unreserved elevator":
            return MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false)
        case "stairs":
            return MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false)
        case "ground floor":
            return .ground
        case .some(_):
            return .defaulted
        case .none:
            break
        }

        switch assessmentAnswer?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ground floor":
            return .ground
        case "stairs":
            return MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false)
        case "reserved elevator":
            return MoveAccess(route: .elevator, elevatorReserved: true, longCarry: false)
        case "elevator":
            return MoveAccess(route: .elevator, elevatorReserved: false, longCarry: false)
        default:
            return .defaulted
        }
    }

    static func specialtyItems(from inventoryItems: [InventoryItem]) -> [SpecialtyItem] {
        inventoryItems
            .filter(\.shouldMove)
            .flatMap { item -> [SpecialtyItem] in
                let name = item.name.lowercased()
                if name.contains("piano") { return [.piano] }
                if name.contains("safe") { return [.safe] }
                if name.contains("pool table") { return [.poolTable] }
                if name.contains("treadmill") { return [.treadmill] }
                if name.contains("marble top") { return [.marbleTops] }
                if name.contains("washer") || name.contains("dryer") || name.contains("refrigerator") {
                    return [.oversizedAppliance]
                }
                return []
            }
    }

    static func makeScope(
        inventoryItems: [InventoryItem],
        assessment: [String: Any],
        packedStatus: PackedStatus,
        reserveAccessAnswers: [String: String] = [:]
    ) -> MoveScope {
        let storageContents = storageContents(from: assessment)
        let cube = cubeResult(
            inventoryItems: inventoryItems,
            bedroomsAnswer: assessment["currentBedrooms"] as? String ?? "",
            storageContents: storageContents
        )
        let hasStorageStop = storageContents != nil
            && (assessment["storageStopOnMovingDay"] as? String)?.lowercased() == "yes"

        return MoveScope(
            cubicFeet: cube.cubicFeet,
            originAccess: access(
                from: assessment["currentFloorAccess"] as? String,
                reservationAnswer: reserveAccessAnswers["RESERVE_ACCESS_OLD"]
            ),
            destAccess: access(
                from: assessment["newFloorAccess"] as? String,
                reservationAnswer: reserveAccessAnswers["RESERVE_ACCESS_NEW"]
            ),
            packedStatus: packedStatus,
            specialtyItems: specialtyItems(from: inventoryItems),
            storageContents: storageContents,
            hasStorageStop: hasStorageStop,
            cubeSource: cube.source
        )
    }
}
