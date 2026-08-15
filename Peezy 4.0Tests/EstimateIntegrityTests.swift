import Testing
@testable import Peezy_4_0

struct EstimateIntegrityPhaseATests {
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
                storageContents: nil
            )
            #expect(result.source == .inventoryScan)
            #expect(result.cubicFeet == expectedCube)
        }

        let withStorage = MoveScopeFactory.cubeResult(
            inventoryItems: [scanItem],
            bedroomsAnswer: "1 Bedroom",
            storageContents: StorageContents(size: "Medium", fullness: "1/2")
        )
        #expect(withStorage.cubicFeet == 390)
    }

    @Test func fallbackCubeDoesNotDoubleApplyHiddenGoods() {
        let result = MoveScopeFactory.cubeResult(
            inventoryItems: [],
            bedroomsAnswer: "1 Bedroom",
            storageContents: nil
        )
        #expect(result.source == .bedroomsFallback)
        #expect(result.cubicFeet == 500)

        let withStorage = MoveScopeFactory.cubeResult(
            inventoryItems: [],
            bedroomsAnswer: "1 Bedroom",
            storageContents: StorageContents(size: "Medium", fullness: "1/2")
        )
        #expect(withStorage.cubicFeet == 710)
    }

    @Test func hiddenGoodsRaiseTheManHourBaseline() {
        let unadjusted = MoveScope(
            cubicFeet: 600,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: .inventoryScan
        )
        let adjustedCube = MoveScopeFactory.cubeResult(
            inventoryItems: [inventoryItem(cubicFeet: 600)],
            bedroomsAnswer: "1 Bedroom",
            storageContents: nil
        )
        let adjusted = MoveScope(
            cubicFeet: adjustedCube.cubicFeet,
            originAccess: .ground,
            destAccess: .ground,
            packedStatus: .packed,
            cubeSource: adjustedCube.source
        )

        #expect(
            PricingEngine.estimatedManHours(for: adjusted)
                > PricingEngine.estimatedManHours(for: unadjusted)
        )
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
}
