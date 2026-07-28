import Foundation
import Testing
@testable import Peezy_4_0

struct MoversBookingPayloadTests {
    @Test func payloadContainsEveryBookingContractSection() throws {
        let identity = PeezyIdentity(
            name: "Test User",
            email: "test@example.com",
            phone: "555-0100",
            currentAddress: PeezyAddress(
                street: "100 Main St", unit: nil, city: "Kansas City",
                state: "MO", zip: "64106", raw: "100 Main St, Kansas City, MO 64106"
            ),
            newAddress: PeezyAddress(
                street: "200 Oak St", unit: "2", city: "Kansas City",
                state: "MO", zip: "64108", raw: "200 Oak St, Kansas City, MO 64108"
            ),
            moveDate: Date(timeIntervalSince1970: 1_800_000_000),
            moveDistanceMiles: 8,
            isInterstate: false
        )
        let scope = MoveScope(
            cubicFeet: 900, driveMinutes: 24,
            originAccess: MoveAccess(route: .stairs, elevatorReserved: false, longCarry: false),
            destAccess: .ground, packedStatus: .packed,
            storageContents: StorageContents(size: "Medium", fullness: "1/2"),
            storageStop: StorageStop(address: "300 Storage Way", usedEstimatedRoute: false),
            cubeSource: .inventoryScan,
            unresolvedUnseenRoomCount: 2
        )
        let tier = VendorValuationTier(
            id: "standard", label: "Standard valuation",
            coveragePerPound: 0.6, additionalCost: 0
        )
        let vendor = Vendor(
            vendorId: "test_mover_a", name: "Test Mover A", vertical: .movers,
            serviceRadius: VendorServiceRadius(center: "Kansas City, MO", miles: 35),
            rateCard: VendorRateCard(
                hourlyByCrew: CrewHourlyRates(two: 145, three: 185, four: 220),
                tripChargeModel: VendorTripCharge(kind: .flat, amount: 129),
                minimumHours: 2, clockPolicy: "portal_to_portal",
                materials: VendorMaterials(included: false, boxBundle: 42, packingPaperBundle: 24),
                valuationTiers: [tier],
                surcharges: VendorSurcharges(weekend: 0.1, monthEnd: 0.08, peakSeason: 0.12),
                specialtyFees: ["piano": 240],
                blackoutDates: []
            ),
            accountability: VendorAccountability(standardsVersion: "v1", strikes: []),
            active: true
        )
        let estimate = PriceEstimate(
            range: PriceRange(low: 700, high: 900), typicalHours: 4.5, crew: 3,
            disclosures: ["Unpacked boxes"], why: "3 movers costs less."
        )
        let payload = MoversBookingPayload(
            identity: identity, scope: scope,
            quote: MoversVendorQuote(vendor: vendor, estimate: estimate, valuationTier: tier),
            quoteRequest: false,
            requestedArrivalWindow: "TEST RUN — 8–10 AM",
            notes: "TEST RUN isolated account"
        ).workflowAnswers()

        #expect(Set(payload.keys) == Set(["identity", "scope", "estimate", "chosen_vendor", "requested_window", "notes", "quoteRequest"]))
        #expect(payload["requested_window"] == ["TEST RUN — 8–10 AM"])
        #expect(payload["quoteRequest"] == ["false"])

        for key in ["identity", "scope", "estimate", "chosen_vendor"] {
            let json = try #require(payload[key]?.first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(!object.isEmpty)
        }

        let scopeJSON = try #require(payload["scope"]?.first)
        let scopeObject = try #require(
            JSONSerialization.jsonObject(with: Data(scopeJSON.utf8)) as? [String: Any]
        )
        #expect((scopeObject["unresolvedUnseenRoomCount"] as? NSNumber)?.intValue == 2)
        let storageContents = try #require(scopeObject["storageContents"] as? [String: Any])
        #expect(storageContents["size"] as? String == "Medium")
        #expect((storageContents["addedCubicFeet"] as? NSNumber)?.doubleValue == 210)
        let storageStop = try #require(scopeObject["storageStop"] as? [String: Any])
        #expect(storageStop["address"] as? String == "300 Storage Way")
        #expect((storageStop["usedEstimatedRoute"] as? NSNumber)?.boolValue == false)

        let contentsOnlyScope = MoveScope(
            cubicFeet: 900,
            driveMinutes: 24,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            storageContents: StorageContents(size: "Medium", fullness: "1/2"),
            cubeSource: .inventoryScan
        )
        let contentsOnlyPayload = MoversBookingPayload(
            identity: identity,
            scope: contentsOnlyScope,
            quote: nil,
            quoteRequest: true,
            requestedArrivalWindow: "TEST RUN — flexible",
            notes: "TEST RUN isolated account"
        ).workflowAnswers()
        let contentsOnlyJSON = try #require(contentsOnlyPayload["scope"]?.first)
        let contentsOnlyObject = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOnlyJSON.utf8)) as? [String: Any]
        )
        #expect(contentsOnlyObject["storageContents"] != nil)
        #expect(contentsOnlyObject["storageStop"] == nil)

        let quoteRequest = MoversBookingPayload(
            identity: identity,
            scope: scope,
            quote: nil,
            quoteRequest: true,
            requestedArrivalWindow: "TEST RUN — flexible",
            notes: "TEST RUN isolated account"
        ).workflowAnswers()

        #expect(Set(quoteRequest.keys) == Set(payload.keys))
        #expect(quoteRequest["quoteRequest"] == ["true"])
        #expect(quoteRequest["requested_window"] == ["TEST RUN — flexible"])

        for key in ["identity", "scope"] {
            let json = try #require(quoteRequest[key]?.first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(!object.isEmpty)
        }

        for key in ["estimate", "chosen_vendor"] {
            let json = try #require(quoteRequest[key]?.first)
            let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(object.isEmpty)
        }
    }
}
