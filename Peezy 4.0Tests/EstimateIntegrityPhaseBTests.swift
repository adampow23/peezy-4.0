import Foundation
import Testing
@testable import Peezy_4_0

struct EstimateIntegrityPhaseBTests {
    @Test func expectedRoomsNormalizeAndKeepScannedExtras() {
        let expected = InventoryCoverage.expectedRooms(
            bedroomsAnswer: "3 Bedrooms",
            dwellingType: "House"
        )
        let report = InventoryCoverage.report(
            expectedRooms: expected,
            scannedRoomNames: ["DEN", "Kitchenette", "Primary Bedroom", "Office"],
            confirmedRoomIDs: []
        )

        #expect(expected.map(\.displayName) == [
            "Living Room", "Kitchen", "Bathroom",
            "Bedroom 1", "Bedroom 2", "Bedroom 3",
            "Garage", "Basement"
        ])
        #expect(report.scannedRoomNames.contains("Office"))
        #expect(report.unresolvedRooms.map(\.displayName).contains("Bedroom 2"))
        #expect(report.unresolvedRooms.map(\.displayName).contains("Bedroom 3"))
        #expect(InventoryCoverage.expectedRooms(
            bedroomsAnswer: "",
            dwellingType: "Apartment"
        ).map(\.displayName) == ["Living Room", "Kitchen", "Bathroom"])

        let duplicateOrdinal = InventoryCoverage.report(
            expectedRooms: expected,
            scannedRoomNames: ["Bedroom 2", "Bedroom 2", "Bedroom 4"],
            confirmedRoomIDs: []
        )
        #expect(
            duplicateOrdinal.unresolvedRooms
                .filter { $0.kind == .bedroom }
                .map(\.displayName) == ["Bedroom 1", "Bedroom 3"]
        )
    }

    @MainActor
    @Test func currentKnowledgeWinsAndAmbiguousLegacyAssessmentsAreNotGuessed() {
        let current = InventoryCoverage.expectationInputs(
            userKnowledgeData: [
                "entries": [
                    "currentBedrooms": ["value": "3 Bedrooms"],
                    "currentDwellingType": ["value": "House"]
                ]
            ],
            legacyAssessmentDocuments: [
                ["currentBedrooms": "1 Bedroom", "currentDwellingType": "Apartment"],
                ["currentBedrooms": "2 Bedrooms", "currentDwellingType": "Condo"]
            ]
        )
        #expect(current == CoverageExpectationInputs(
            bedroomsAnswer: "3 Bedrooms",
            dwellingType: "House"
        ))

        let ambiguous = InventoryCoverage.expectationInputs(
            userKnowledgeData: nil,
            legacyAssessmentDocuments: [
                ["currentBedrooms": "1 Bedroom", "currentDwellingType": "Apartment"],
                ["currentBedrooms": "2 Bedrooms", "currentDwellingType": "House"]
            ]
        )
        #expect(ambiguous == CoverageExpectationInputs(bedroomsAnswer: "", dwellingType: ""))
    }

    @MainActor
    @Test func concurrentConfirmationFailureDoesNotDiscardAnotherSuccess() async throws {
        let store = InterleavingCoverageConfirmationStore()
        let manager = InventorySessionManager(
            coverageConfirmationStore: store,
            userIDProvider: { "phase-b-test-user" }
        )
        manager.configureCoverage(bedroomsAnswer: "1 Bedroom", dwellingType: "House")
        let garage = try #require(manager.expectedCoverageRooms.first { $0.id == "garage" })
        let basement = try #require(manager.expectedCoverageRooms.first { $0.id == "basement" })

        let failingTask = Task { await manager.confirmNothingThere(garage) }
        await store.waitUntilFailureIsSuspended()
        let succeedingTask = Task { await manager.confirmNothingThere(basement) }
        await succeedingTask.value
        await failingTask.value

        #expect(manager.coverageConfirmedRoomIDs == ["basement"])
        #expect(store.persistedRoomIDs == ["basement"])
    }

    @Test func bothCoverageActionsRoundTrip() throws {
        let expected = InventoryCoverage.expectedRooms(
            bedroomsAnswer: "2 Bedrooms",
            dwellingType: "House"
        )
        let initial = InventoryCoverage.report(
            expectedRooms: expected,
            scannedRoomNames: ["Living Room", "Kitchen", "Bathroom", "Bedroom 1"],
            confirmedRoomIDs: []
        )
        let bedroomClip = try #require(initial.unresolvedRooms.first { $0.id == "bedroom-2" })

        let afterClip = InventoryCoverage.report(
            expectedRooms: expected,
            scannedRoomNames: initial.scannedRoomNames + [bedroomClip.displayName],
            confirmedRoomIDs: []
        )
        #expect(!afterClip.unresolvedRooms.contains { $0.id == "bedroom-2" })

        let metadata = InventoryCoverage.metadata(confirmedRoomIDs: ["garage", "basement"])
        let decoded = InventoryCoverage.confirmedRoomIDs(fromMetadata: metadata)
        #expect(decoded == Set(["garage", "basement"]))
        let resolved = InventoryCoverage.report(
            expectedRooms: expected,
            scannedRoomNames: afterClip.scannedRoomNames,
            confirmedRoomIDs: decoded
        )
        #expect(resolved.unresolvedRooms.isEmpty)
    }

}

@MainActor
private final class InterleavingCoverageConfirmationStore: CoverageConfirmationPersisting {
    private enum ExpectedFailure: Error { case writeRejected }

    private var failedWriteContinuation: CheckedContinuation<Void, Never>?
    private(set) var failureIsSuspended = false
    private(set) var persistedRoomIDs: Set<String> = []

    func insertConfirmedRoomID(_ roomID: String, userID: String) async throws -> Set<String> {
        if roomID == "garage" {
            failureIsSuspended = true
            await withCheckedContinuation { continuation in
                failedWriteContinuation = continuation
            }
            throw ExpectedFailure.writeRejected
        }

        persistedRoomIDs.insert(roomID)
        failedWriteContinuation?.resume()
        failedWriteContinuation = nil
        return persistedRoomIDs
    }

    func waitUntilFailureIsSuspended() async {
        while !failureIsSuspended { await Task.yield() }
    }
}
