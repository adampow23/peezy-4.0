import Foundation
import Testing
@testable import Peezy_4_0

@MainActor
struct EstimateIntegrityPhaseDTests {
    private let disclosure = "Storage stop estimated — add the unit's address to tighten this."

    @Test func storageContentsWithoutMovingDayStopAddCubeOnly() async {
        let estimator = StubMoveRouteEstimator(routes: ["origin→destination": 22])
        let scope = await MoveScopeFactory.makeScope(
            inventoryItems: [],
            assessment: assessment(stopOnMovingDay: false),
            identity: identity,
            packedStatus: .packed,
            routeEstimator: estimator
        )

        #expect(scope.cubicFeet == 710)
        #expect(scope.storageContents == StorageContents(size: "Medium", fullness: "1/2"))
        #expect(scope.storageStop == nil)
        #expect(scope.driveMinutes == 22)
        #expect(!PricingEngine.disclosures(for: scope).contains(disclosure))
        #expect(await estimator.recordedCalls() == ["origin→destination"])
    }

    @Test func addressedStorageStopSumsBothLegsAndAddsLockedLoadTime() async {
        let estimator = StubMoveRouteEstimator(routes: [
            "origin→storage": 12,
            "storage→destination": 18
        ])
        let scope = await MoveScopeFactory.makeScope(
            inventoryItems: [],
            assessment: assessment(stopOnMovingDay: true, address: "storage"),
            identity: identity,
            packedStatus: .packed,
            routeEstimator: estimator
        )
        let withoutStop = MoveScope(
            cubicFeet: scope.cubicFeet,
            driveMinutes: scope.driveMinutes,
            originAccess: scope.originAccess,
            destAccess: scope.destAccess,
            packedStatus: scope.packedStatus,
            storageContents: scope.storageContents,
            cubeSource: scope.cubeSource
        )

        #expect(scope.driveMinutes == 30)
        #expect(scope.storageStop == StorageStop(address: "storage", usedEstimatedRoute: false))
        #expect(PricingEngine.physicalHours(for: scope, crew: 4)
            == PricingEngine.physicalHours(for: withoutStop, crew: 4) + 0.75)
        #expect(!PricingEngine.disclosures(for: scope).contains(disclosure))
        #expect(await estimator.recordedCalls() == ["origin→storage", "storage→destination"])
    }

    @Test func missingAddressUsesDirectETAPlusThirtyAndDiscloses() async {
        let estimator = StubMoveRouteEstimator(routes: ["origin→destination": 22])
        let scope = await MoveScopeFactory.makeScope(
            inventoryItems: [],
            assessment: assessment(stopOnMovingDay: true, address: nil),
            identity: identity,
            packedStatus: .packed,
            routeEstimator: estimator
        )

        #expect(scope.driveMinutes == 52)
        #expect(scope.storageStop == StorageStop(address: nil, usedEstimatedRoute: true))
        #expect(PricingEngine.disclosures(for: scope).contains(disclosure))
        #expect(await estimator.recordedCalls() == ["origin→destination"])
    }

    @Test func failedStorageLegUsesDirectETAPlusThirtyAndDiscloses() async {
        let estimator = StubMoveRouteEstimator(routes: [
            "origin→storage": 12,
            "origin→destination": 22
        ])
        let scope = await MoveScopeFactory.makeScope(
            inventoryItems: [],
            assessment: assessment(stopOnMovingDay: true, address: "storage"),
            identity: identity,
            packedStatus: .packed,
            routeEstimator: estimator
        )

        #expect(scope.driveMinutes == 52)
        #expect(scope.storageStop?.usedEstimatedRoute == true)
        #expect(PricingEngine.disclosures(for: scope).contains(disclosure))
        #expect(await estimator.recordedCalls() == [
            "origin→storage", "storage→destination", "origin→destination"
        ])
    }

    @Test func unavailableDirectRouteKeepsExistingFallbackThenAddsThirty() async {
        let estimator = StubMoveRouteEstimator(routes: [:])
        let scope = await MoveScopeFactory.makeScope(
            inventoryItems: [],
            assessment: assessment(stopOnMovingDay: true, address: nil),
            identity: identity,
            packedStatus: .packed,
            routeEstimator: estimator
        )

        #expect(scope.driveMinutes == 60)
        #expect(scope.storageStop?.usedEstimatedRoute == true)
        #expect(PricingEngine.disclosures(for: scope).contains(disclosure))
    }

    @Test func stopLoadTimeCrossesUnroundedConciergeCeiling() {
        let withoutStop = MoveScope(
            cubicFeet: 1_127.5,
            driveMinutes: 0,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        let withStop = MoveScope(
            cubicFeet: 1_127.5,
            driveMinutes: 0,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            storageStop: StorageStop(address: "storage", usedEstimatedRoute: false),
            cubeSource: .inventoryScan
        )

        #expect(PricingEngine.physicalHours(for: withoutStop, crew: 4) == 5.5)
        #expect(PricingEngine.physicalHours(for: withStop, crew: 4) == 6.25)
        #expect(PricingEngine.quoteRoute(scope: withoutStop, largestAvailableCrewSize: 4) == .instantComparison)
        #expect(PricingEngine.quoteRoute(scope: withStop, largestAvailableCrewSize: 4) == .conciergeQuote)
    }

    private var identity: PeezyIdentity {
        PeezyIdentity(
            name: "Test User",
            email: "test@example.com",
            currentAddress: address("origin"),
            newAddress: address("destination"),
            moveDistanceMiles: 8,
            isInterstate: false
        )
    }

    private func address(_ raw: String) -> PeezyAddress {
        PeezyAddress(street: raw, unit: nil, city: "Kansas City", state: "MO", zip: "64106", raw: raw)
    }

    private func assessment(stopOnMovingDay: Bool, address: String? = nil) -> [String: Any] {
        var value: [String: Any] = [
            "hasStorage": "Yes",
            "storageSize": "Medium",
            "storageFullness": "1/2",
            "storageStopOnMovingDay": stopOnMovingDay ? "Yes" : "No",
            "currentBedrooms": "1 Bedroom",
            "currentFloorAccess": "Ground Floor",
            "newFloorAccess": "Ground Floor"
        ]
        if let address { value["storageUnitAddress"] = address }
        return value
    }
}

private actor StubMoveRouteEstimator: MoveRouteEstimating {
    private let routes: [String: Double]
    private var calls: [String] = []

    init(routes: [String: Double]) {
        self.routes = routes
    }

    func etaMinutes(from: String, to: String) async -> Double? {
        let key = "\(from)→\(to)"
        calls.append(key)
        return routes[key]
    }

    func recordedCalls() -> [String] {
        calls
    }
}
