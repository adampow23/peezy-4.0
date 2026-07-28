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

protocol MoveRouteEstimating {
    func etaMinutes(from: String, to: String) async -> Double?
}

struct MapKitMoveRouteEstimator: MoveRouteEstimating {
    nonisolated init() {}

    func etaMinutes(from: String, to: String) async -> Double? {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty else { return nil }

        do {
            let geocoder = CLGeocoder()
            guard let originPlacemark = try await geocoder.geocodeAddressString(trimmedFrom).first,
                  let destinationPlacemark = try await geocoder.geocodeAddressString(trimmedTo).first
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

    static func storageContents(from assessment: [String: Any]) -> StorageContents? {
        guard (assessment["hasStorage"] as? String)?.lowercased() == "yes",
              let size = assessment["storageSize"] as? String,
              let fullness = assessment["storageFullness"] as? String,
              !size.isEmpty,
              !fullness.isEmpty
        else { return nil }
        return StorageContents(size: size, fullness: fullness)
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
        unresolvedUnseenRoomCount: Int = 0,
        routeEstimator: any MoveRouteEstimating = MapKitMoveRouteEstimator()
    ) async -> MoveScope {
        let storageContents = storageContents(from: assessment)
        let bedrooms = (assessment["currentBedrooms"] as? String) ?? ""
        let cube = cubeResult(
            inventoryItems: inventoryItems,
            bedroomsAnswer: bedrooms,
            storageContents: storageContents
        )
        let route = await driveRoute(
            identity: identity,
            assessment: assessment,
            estimator: routeEstimator
        )

        return MoveScope(
            cubicFeet: cube.cubicFeet,
            driveMinutes: route.minutes,
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
            storageStop: route.storageStop,
            serviceDate: identity.moveDate,
            cubeSource: cube.source,
            unresolvedUnseenRoomCount: unresolvedUnseenRoomCount
        )
    }

    private struct DriveRoute {
        let minutes: Double
        let storageStop: StorageStop?
    }

    /// Uses identity addresses for the direct route. An addressed storage stop
    /// replaces that route with two real legs. Missing/failed stop routing keeps
    /// the direct ETA and adds the locked 30-minute allowance.
    private static func driveRoute(
        identity: PeezyIdentity,
        assessment: [String: Any],
        estimator: any MoveRouteEstimating
    ) async -> DriveRoute {
        let origin = identity.currentAddress?.raw.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destination = identity.newAddress?.raw.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasStorage = (assessment["hasStorage"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "yes"
        let isMovingDayStop = hasStorage && (assessment["storageStopOnMovingDay"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "yes"

        guard isMovingDayStop else {
            let direct = await estimator.etaMinutes(from: origin, to: destination)
                ?? PricingConstants.defaultDriveMinutes
            return DriveRoute(minutes: direct, storageStop: nil)
        }

        let address = (assessment["storageUnitAddress"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAddress = address?.isEmpty == false ? address : nil
        if let normalizedAddress,
           let firstLeg = await estimator.etaMinutes(from: origin, to: normalizedAddress),
           let secondLeg = await estimator.etaMinutes(from: normalizedAddress, to: destination) {
            return DriveRoute(
                minutes: firstLeg + secondLeg,
                storageStop: StorageStop(address: normalizedAddress, usedEstimatedRoute: false)
            )
        }

        let direct = await estimator.etaMinutes(from: origin, to: destination)
            ?? PricingConstants.defaultDriveMinutes
        return DriveRoute(
            minutes: direct + PricingConstants.storageStopFallbackDriveMinutes,
            storageStop: StorageStop(address: normalizedAddress, usedEstimatedRoute: true)
        )
    }
}
