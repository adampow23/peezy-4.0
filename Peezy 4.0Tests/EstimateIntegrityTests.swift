import Foundation
import Testing
@testable import Peezy_4_0

struct EstimateIntegrityPhaseATests {
    private let hiddenGoodsDisclosure = "Includes what scans can't see — closets, cabinets, drawers."

    @Test func scanCubeAddsBedroomFactorExactlyOnce() {
        let scanItem = inventoryItem(cubicFeet: 100)
        let cases: [(String, Double)] = [
            ("1 Bedroom", 180),
            ("2 Bedrooms", 240),
            ("3 Bedrooms", 320),
            ("4 Bedrooms", 400),
            ("6+ Bedrooms", 400)
        ]

        for (bedrooms, expectedCube) in cases {
            let result = MoveScopeFactory.cubeResult(
                inventoryItems: [scanItem],
                bedroomsAnswer: bedrooms,
                storageStop: nil
            )
            #expect(result.source == .inventoryScan)
            #expect(result.cubicFeet == expectedCube)
        }

        let withStorage = MoveScopeFactory.cubeResult(
            inventoryItems: [scanItem],
            bedroomsAnswer: "1 Bedroom",
            storageStop: StorageStop(size: "Medium", fullness: "1/2")
        )
        #expect(withStorage.cubicFeet == 390)
    }

    @Test func fallbackCubeDoesNotDoubleApplyHiddenGoods() {
        let result = MoveScopeFactory.cubeResult(
            inventoryItems: [],
            bedroomsAnswer: "1 Bedroom",
            storageStop: nil
        )

        #expect(result.source == .bedroomsFallback)
        #expect(result.cubicFeet == 500)

        let withStorage = MoveScopeFactory.cubeResult(
            inventoryItems: [],
            bedroomsAnswer: "1 Bedroom",
            storageStop: StorageStop(size: "Medium", fullness: "1/2")
        )
        #expect(withStorage.cubicFeet == 710)
    }

    @Test func hiddenGoodsRaisesBothRangeBoundsAndAddsLockedDisclosure() throws {
        let rateCard = PricingRateCard(
            hourlyByCrew: [2: 100, 3: 150, 4: 210],
            tripCharge: 50,
            minimumHours: 2
        )
        let unadjusted = MoveScope(
            cubicFeet: 600,
            driveMinutes: 0,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        let adjustedCube = MoveScopeFactory.cubeResult(
            inventoryItems: [inventoryItem(cubicFeet: 600)],
            bedroomsAnswer: "1 Bedroom",
            storageStop: nil
        )
        let adjusted = MoveScope(
            cubicFeet: adjustedCube.cubicFeet,
            driveMinutes: 0,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: adjustedCube.source
        )

        let before = try #require(PricingEngine.estimate(scope: unadjusted, rateCard: rateCard))
        let after = try #require(PricingEngine.estimate(scope: adjusted, rateCard: rateCard))
        #expect(after.range.low > before.range.low)
        #expect(after.range.high > before.range.high)
        #expect(after.disclosures.contains(hiddenGoodsDisclosure))

        let fallback = MoveScope(
            cubicFeet: 500,
            driveMinutes: 0,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .bedroomsFallback
        )
        let fallbackEstimate = try #require(PricingEngine.estimate(scope: fallback, rateCard: rateCard))
        #expect(!fallbackEstimate.disclosures.contains(hiddenGoodsDisclosure))
    }

    @Test func comparisonCardCarriesEstimateDisclosure() {
        let estimate = PriceEstimate(
            range: PriceRange(low: 500, high: 700),
            typicalHours: 4,
            crew: 2,
            disclosures: [hiddenGoodsDisclosure],
            why: "Sized for the move."
        )
        let tier = VendorValuationTier(
            id: "standard",
            label: "Standard valuation",
            coveragePerPound: 0.6,
            additionalCost: 0
        )
        let quote = MoversVendorQuote(
            vendor: vendor(tier: tier),
            estimate: estimate,
            valuationTier: tier
        )

        let model = quote.comparisonModel(arrivalWindow: "8–10 AM", priceBasis: "your scan")
        #expect(model.detailNotes.contains(hiddenGoodsDisclosure))
    }

    private func inventoryItem(cubicFeet: Double) -> InventoryItem {
        InventoryItem(
            id: "scan-item",
            name: "Unclassified item",
            category: "other",
            tier: "furniture",
            quantity: 1,
            sizeEstimate: "medium",
            cubicFeet: cubicFeet,
            isFragile: false,
            isHighValue: false,
            confidence: 0.9,
            frameIndex: 0,
            boundingBox: nil,
            roomName: "Living Room",
            shouldMove: true,
            notes: ""
        )
    }

    private func vendor(tier: VendorValuationTier) -> Vendor {
        Vendor(
            vendorId: "test-mover",
            name: "Test Mover",
            vertical: .movers,
            serviceRadius: VendorServiceRadius(center: "Kansas City, MO", miles: 30),
            rateCard: VendorRateCard(
                hourlyByCrew: CrewHourlyRates(two: 100, three: 150, four: 210),
                tripChargeModel: VendorTripCharge(kind: .flat, amount: 50),
                minimumHours: 2,
                clockPolicy: "portal_to_portal",
                materials: VendorMaterials(included: false, boxBundle: 0, packingPaperBundle: 0),
                valuationTiers: [tier],
                surcharges: VendorSurcharges(weekend: 0, monthEnd: 0, peakSeason: 0),
                specialtyFees: [:],
                blackoutDates: []
            ),
            accountability: VendorAccountability(standardsVersion: "v1", strikes: []),
            active: true
        )
    }
}
