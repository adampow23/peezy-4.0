import FirebaseAuth
import FirebaseFirestore
import XCTest
@testable import Peezy_4_0

final class CoverageFirestoreIntegrationTests: XCTestCase {
    @MainActor
    func testNothingThereSurvivesRealFirestoreWriteAndReadBack() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PEEZY_RUN_FIRESTORE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set PEEZY_RUN_FIRESTORE_INTEGRATION=1 for the bounded test-bot check.")
        }
        let email = try XCTUnwrap(environment["PEEZY_TEST_BOT_EMAIL"])
        let password = try XCTUnwrap(environment["PEEZY_TEST_BOT_PASSWORD"])

        let auth = Auth.auth()
        let authResult = try await auth.signIn(withEmail: email, password: password)
        let userID = authResult.user.uid
        let metadataRef = Firestore.firestore().collection("users").document(userID)
            .collection("inventory").document("_metadata")
        let previous = try await metadataRef.getDocument()

        var testError: Error?
        do {
            try await metadataRef.setData([
                InventoryCoverage.confirmedMetadataKey: []
            ], merge: true)

            let manager = InventorySessionManager(
                coverageConfirmationStore: FirestoreCoverageConfirmationStore(),
                userIDProvider: { userID }
            )
            manager.configureCoverage(bedroomsAnswer: "1 Bedroom", dwellingType: "House")
            let basement = try XCTUnwrap(
                manager.expectedCoverageRooms.first { $0.id == "basement" }
            )

            await manager.confirmNothingThere(basement)
            XCTAssertNil(manager.error)
            XCTAssertTrue(manager.coverageConfirmedRoomIDs.contains("basement"))

            let readBack = try await metadataRef.getDocument()
            XCTAssertTrue(
                InventoryCoverage.confirmedRoomIDs(fromMetadata: readBack.data() ?? [:])
                    .contains("basement")
            )
        } catch {
            testError = error
        }

        do {
            if previous.exists, let data = previous.data() {
                try await metadataRef.setData(data)
                let restored = try await metadataRef.getDocument()
                XCTAssertEqual(
                    InventoryCoverage.confirmedRoomIDs(fromMetadata: restored.data() ?? [:]),
                    InventoryCoverage.confirmedRoomIDs(fromMetadata: data)
                )
            } else {
                try await metadataRef.delete()
                let restored = try await metadataRef.getDocument()
                XCTAssertFalse(restored.exists)
            }
        } catch {
            if testError == nil { testError = error }
        }
        try? auth.signOut()
        if let testError { throw testError }
    }
}
