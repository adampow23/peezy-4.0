//
//  MoveScopeFactory.swift
//  Peezy 4.0
//
//  App-bound scope assembly. The pricing math remains in PricingEngine.swift;
//  this file is the narrow bridge from inventory, assessment answers, and
//  MapKit's route ETA into the pure MoveScope value.
//

import CoreLocation
import Foundation
import MapKit

enum MoveScopeFactory {
    struct CubeResult: Equatable {
        let cubicFeet: Double
        let source: CubeSource
    }

    static func cubeResult(
        inventoryItems: [InventoryItem],
        bedroomsAnswer: String,
        storageStop: StorageStop?
    ) -> CubeResult {
        let storageCube = storageStop?.addedCubicFeet ?? 0
        let includedItems = inventoryItems.filter(\.shouldMove)
        guard !includedItems.isEmpty else {
            // The bedroom fallback ranges already model closets, cabinets, and
            // drawers. Applying the scan-only allowance here would count them twice.
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

    static func storageStop(from assessment: [String: Any]) -> StorageStop? {
        guard (assessment["hasStorage"] as? String)?.lowercased() == "yes",
              let size = assessment["storageSize"] as? String,
              let fullness = assessment["storageFullness"] as? String,
              !size.isEmpty,
              !fullness.isEmpty
        else { return nil }
        return StorageStop(size: size, fullness: fullness)
    }

    /// A completed RESERVE_ACCESS task can supply a fresher access selection
    /// than the assessment. Phase C passes those two task-answer values by the
    /// task IDs below; until then, assessment values remain the safe fallback.
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
        identity: PeezyIdentity,
        packedStatus: PackedStatus,
        reserveAccessAnswers: [String: String] = [:],
        unresolvedUnseenRoomCount: Int = 0
    ) async -> MoveScope {
        let storageStop = storageStop(from: assessment)
        let bedrooms = (assessment["currentBedrooms"] as? String) ?? ""
        let cube = cubeResult(
            inventoryItems: inventoryItems,
            bedroomsAnswer: bedrooms,
            storageStop: storageStop
        )
        let driveMinutes = await etaMinutes(
            from: identity.currentAddress,
            to: identity.newAddress
        ) ?? PricingConstants.defaultDriveMinutes

        return MoveScope(
            cubicFeet: cube.cubicFeet,
            driveMinutes: driveMinutes,
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
            storageStop: storageStop,
            serviceDate: identity.moveDate,
            cubeSource: cube.source,
            unresolvedUnseenRoomCount: unresolvedUnseenRoomCount
        )
    }

    /// Uses the identity addresses, rather than a hand-entered distance field,
    /// so the quote's drive time is the same ETA a mover would inspect.
    static func etaMinutes(from origin: PeezyAddress?, to destination: PeezyAddress?) async -> Double? {
        guard let origin, let destination,
              !origin.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !destination.raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        do {
            let geocoder = CLGeocoder()
            guard let originPlacemark = try await geocoder.geocodeAddressString(origin.raw).first,
                  let destinationPlacemark = try await geocoder.geocodeAddressString(destination.raw).first
            else { return nil }

            let request = MKDirections.Request()
            request.transportType = .automobile
            request.source = MKMapItem(placemark: MKPlacemark(placemark: originPlacemark))
            request.destination = MKMapItem(placemark: MKPlacemark(placemark: destinationPlacemark))
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return route.expectedTravelTime / 60
        } catch {
            return nil
        }
    }
}
