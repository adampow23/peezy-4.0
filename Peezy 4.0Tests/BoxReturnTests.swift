import Foundation
import Testing
@testable import Peezy_4_0

struct BoxReturnTests {
    @Test func deliveredCountComesFromSubmittedKitEnvelope() throws {
        let kit: [String: Any] = [
            "small": 4,
            "medium": 5,
            "large": 3,
            "wardrobe": 2,
            "dishPack": 1,
            "tape": 2,
            "paper": 1
        ]
        let encoded = String(
            data: try JSONSerialization.data(withJSONObject: kit),
            encoding: .utf8
        )!
        let response: [String: Any] = [
            "answers": [
                "workflowId": "supplies_kit",
                "answers": ["kit": [encoded]]
            ]
        ]

        #expect(BoxReturnService.deliveredBoxCount(fromWorkflowResponse: response) == 15)
    }

    @Test func malformedOrNegativeKitDoesNotProduceCalibrationInput() throws {
        let negativeKit: [String: Any] = [
            "small": -1,
            "medium": 5,
            "large": 3,
            "wardrobe": 2,
            "dishPack": 1
        ]
        let encoded = String(
            data: try JSONSerialization.data(withJSONObject: negativeKit),
            encoding: .utf8
        )!

        #expect(BoxReturnService.deliveredBoxCount(fromWorkflowResponse: [:]) == nil)
        #expect(BoxReturnService.deliveredBoxCount(fromWorkflowResponse: [
            "answers": ["answers": ["kit": [encoded]]]
        ]) == nil)
    }

    @Test func calibrationRoundTripAndPickupPayloadKeepExactCounts() {
        let calibration = BoxReturnService.calibration(fromFirestore: [
            "delivered": 15,
            "returned": 9
        ])
        let payload = BoxReturnService.pickupPayload(
            userId: "user-123",
            returned: 9
        )

        #expect(calibration == KitCalibration(delivered: 15, returned: 9))
        #expect(calibration?.firestoreData == ["delivered": 15, "returned": 9])
        #expect(payload["taskId"] as? String == "BOX_RETURN")
        #expect(payload["taskTitle"] as? String == "Pick up 9 returned boxes")
        #expect(payload["taskCategory"] as? String == "packing")
        #expect(payload["userId"] as? String == "user-123")
    }
}
