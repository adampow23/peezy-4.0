//
//  MoversBookingPayload.swift
//  Peezy 4.0
//
//  Serializes the full mover booking context into the existing
//  WorkflowAnswers string-array envelope consumed by submitWorkflowAnswers.
//

import Foundation

struct MoversBookingPayload {
    let identity: PeezyIdentity
    let scope: MoveScope
    let quote: MoversVendorQuote?
    let quoteRequest: Bool
    let requestedArrivalWindow: String
    let notes: String

    func workflowAnswers() -> [String: [String]] {
        [
            "identity": [Self.jsonString(identityObject)],
            "scope": [Self.jsonString(scopeObject)],
            "estimate": [Self.jsonString(estimateObject)],
            "chosen_vendor": [Self.jsonString(vendorObject)],
            "requested_window": [requestedArrivalWindow],
            "notes": [notes],
            "quoteRequest": [quoteRequest ? "true" : "false"]
        ]
    }

    private var identityObject: [String: Any] {
        var object: [String: Any] = [
            "name": identity.name,
            "email": identity.email,
            "phone": identity.phone ?? "",
            "currentAddress": Self.addressObject(identity.currentAddress),
            "newAddress": Self.addressObject(identity.newAddress),
            "moveDistanceMiles": identity.moveDistanceMiles ?? 0,
            "isInterstate": identity.isInterstate ?? false,
            "newAddressPending": identity.newAddressPending ?? false,
            "moveDatePending": identity.moveDatePending ?? false
        ]
        if let moveDate = identity.moveDate {
            object["moveDate"] = moveDate.formatted(.iso8601)
        }
        return object
    }

    private var scopeObject: [String: Any] {
        var object: [String: Any] = [
            "cubicFeet": scope.cubicFeet,
            "driveMinutes": scope.driveMinutes,
            "originAccess": Self.accessObject(scope.originAccess),
            "destinationAccess": Self.accessObject(scope.destAccess),
            "packedStatus": scope.packedStatus.rawValue,
            "specialtyItems": scope.specialtyItems.map(\.rawValue),
            "cubeSource": scope.cubeSource.rawValue
        ]
        if let storage = scope.storageStop {
            object["storageStop"] = [
                "size": storage.size,
                "fullness": storage.fullness,
                "addedCubicFeet": storage.addedCubicFeet
            ]
        }
        return object
    }

    private var estimateObject: [String: Any] {
        guard let quote else { return [:] }
        return [
            "low": quote.estimate.range.low,
            "high": quote.estimate.range.high,
            "typicalHours": quote.estimate.typicalHours,
            "crew": quote.estimate.crew,
            "disclosures": quote.estimate.disclosures,
            "why": quote.estimate.why,
            "insuranceTierId": quote.valuationTier.id,
            "insuranceTier": quote.valuationTier.label,
            "insuranceAdditionalCost": quote.valuationTier.additionalCost,
            "specialtyHandlingNotes": quote.estimate.specialtyHandlingNotes
        ]
    }

    private var vendorObject: [String: Any] {
        guard let quote else { return [:] }
        return [
            "vendorId": quote.vendor.vendorId,
            "name": quote.vendor.name,
            "vertical": quote.vendor.vertical.rawValue,
            "serviceRadius": [
                "center": quote.vendor.serviceRadius.center,
                "miles": quote.vendor.serviceRadius.miles
            ],
            "rateCard": [
                "hourlyByCrew": [
                    "2": quote.vendor.rateCard.hourlyByCrew.two,
                    "3": quote.vendor.rateCard.hourlyByCrew.three,
                    "4": quote.vendor.rateCard.hourlyByCrew.four
                ],
                "tripCharge": quote.vendor.rateCard.tripChargeModel.amount,
                "minimumHours": quote.vendor.rateCard.minimumHours,
                "clockPolicy": quote.vendor.rateCard.clockPolicy,
                "specialtyFees": quote.vendor.rateCard.specialtyFees
            ],
            "accountability": [
                "standardsVersion": quote.vendor.accountability.standardsVersion,
                "strikes": quote.vendor.accountability.strikes
            ]
        ]
    }

    private static func addressObject(_ address: PeezyAddress?) -> [String: Any] {
        guard let address else { return [:] }
        return [
            "street": address.street,
            "unit": address.unit ?? "",
            "city": address.city,
            "state": address.state,
            "zip": address.zip,
            "raw": address.raw
        ]
    }

    private static func accessObject(_ access: MoveAccess) -> [String: Any] {
        [
            "route": access.route.rawValue,
            "elevatorReserved": access.elevatorReserved,
            "longCarry": access.longCarry
        ]
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
