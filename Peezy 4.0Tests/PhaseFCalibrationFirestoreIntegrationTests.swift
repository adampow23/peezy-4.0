import FirebaseAuth
import FirebaseFirestore
import XCTest
@testable import Peezy_4_0

final class PhaseFCalibrationFirestoreIntegrationTests: XCTestCase {
    @MainActor
    func testKitRanOutAndFinalBillPersistForSignedTestBot() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PEEZY_RUN_FIRESTORE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set PEEZY_RUN_FIRESTORE_INTEGRATION=1 for the bounded test-bot check.")
        }
        let email = try XCTUnwrap(environment["PEEZY_TEST_BOT_EMAIL"])
        let password = try XCTUnwrap(environment["PEEZY_TEST_BOT_PASSWORD"])

        let auth = Auth.auth()
        let authResult = try await auth.signIn(withEmail: email, password: password)
        let userID = authResult.user.uid
        let db = Firestore.firestore()
        let userRef = db.collection("users").document(userID)
        let kitResponseRef = userRef.collection("workflowResponses").document("supplies_kit")
        let bookingResponseRef = userRef.collection("workflowResponses").document("book_movers")
        let previousUser = try await userRef.getDocument()
        let previousKitResponse = try await kitResponseRef.getDocument()
        let previousBookingResponse = try await bookingResponseRef.getDocument()

        var testError: Error?
        var reviewID: String?
        var calibrationID: String?
        do {
            try await kitResponseRef.setData([
                "workflowId": "supplies_kit",
                "answers": [
                    "workflowId": "supplies_kit",
                    "answers": [
                        "kit": [try json([
                            "small": 4,
                            "medium": 5,
                            "large": 3,
                            "wardrobe": 2,
                            "dishPack": 1
                        ])]
                    ]
                ]
            ])
            let kitCalibration = try await BoxReturnService().submit(
                userId: userID,
                returned: 9,
                ranOut: true,
                requestPickup: false
            )
            XCTAssertTrue(kitCalibration.ranOut)
            let kitReadback = try await userRef.getDocument()
            let rawKit = try XCTUnwrap(kitReadback.data()?["kitCalibration"] as? [String: Any])
            XCTAssertEqual(BoxReturnService.calibration(fromFirestore: rawKit), kitCalibration)

            try await bookingResponseRef.setData([
                "workflowId": "book_movers",
                "answers": [
                    "workflowId": "book_movers",
                    "answers": [
                        "chosen_vendor": [try json([
                            "vendorId": "phase_f_calibration_fixture",
                            "name": "Phase F Calibration Fixture"
                        ])],
                        "estimate": [try json(["low": 1_200, "high": 1_600])],
                        "scope": [try json([
                            "cubicFeet": 980,
                            "driveMinutes": 45,
                            "packedStatus": "mostlyPacked"
                        ])],
                        "quoteRequest": ["false"]
                    ]
                ]
            ])
            let checkIn = try await CheckInService().submit(MoveCheckInAnswers(
                arrivedInWindow: true,
                crewWorkedSteadily: true,
                costMoreThanQuoted: false,
                damaged: false,
                note: "Phase F bounded verification",
                finalBill: 1_432.18
            ))
            reviewID = checkIn.reviewId
            calibrationID = try XCTUnwrap(checkIn.calibrationId)
            XCTAssertEqual(checkIn.vendorId, "phase_f_calibration_fixture")
        } catch {
            testError = error
        }

        do {
            try await restore(previousKitResponse, at: kitResponseRef)
            try await restore(previousBookingResponse, at: bookingResponseRef)
            if let previousCalibration = previousUser.data()?["kitCalibration"] {
                try await userRef.setData(["kitCalibration": previousCalibration], merge: true)
            } else if previousUser.exists {
                try await userRef.updateData(["kitCalibration": FieldValue.delete()])
            }
        } catch {
            if testError == nil { testError = error }
        }

        try? auth.signOut()
        if let reviewID {
            print("PHASE_F_REVIEW_ID=\(reviewID)")
        }
        if let calibrationID {
            print("PHASE_F_CALIBRATION_ID=\(calibrationID)")
        }
        if let testError { throw testError }
    }

    private func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func restore(_ snapshot: DocumentSnapshot, at reference: DocumentReference) async throws {
        if snapshot.exists, let data = snapshot.data() {
            try await reference.setData(data)
        } else {
            try await reference.delete()
        }
    }
}
