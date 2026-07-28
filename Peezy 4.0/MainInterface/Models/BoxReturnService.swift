import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct KitCalibration: Equatable {
    let delivered: Int
    let returned: Int
    let ranOut: Bool

    var firestoreData: [String: Any] {
        [
            "delivered": delivered,
            "returned": returned,
            "ranOut": ranOut
        ]
    }
}

struct BoxReturnService {
    private let db: Firestore
    private let functions: Functions

    init(
        db: Firestore = Firestore.firestore(),
        functions: Functions = Functions.functions()
    ) {
        self.db = db
        self.functions = functions
    }

    func loadDeliveredCount(userId: String) async throws -> Int {
        guard !userId.isEmpty else { throw BoxReturnServiceError.missingUser }
        let snapshot = try await db.collection("users").document(userId)
            .collection("workflowResponses").document("supplies_kit")
            .getDocument()
        guard let data = snapshot.data(),
              let delivered = Self.deliveredBoxCount(fromWorkflowResponse: data)
        else {
            throw BoxReturnServiceError.missingKitOrder
        }
        return delivered
    }

    func submit(
        userId: String,
        returned: Int,
        ranOut: Bool,
        requestPickup: Bool
    ) async throws -> KitCalibration {
        guard !userId.isEmpty else { throw BoxReturnServiceError.missingUser }
        guard returned >= 0 else { throw BoxReturnServiceError.invalidReturnedCount }

        let delivered = try await loadDeliveredCount(userId: userId)
        let calibration = KitCalibration(
            delivered: delivered,
            returned: returned,
            ranOut: ranOut
        )
        let userRef = db.collection("users").document(userId)
        try await userRef.setData(
            ["kitCalibration": calibration.firestoreData],
            merge: true
        )

        let readback = try await userRef.getDocument()
        guard let rawCalibration = readback.data()?["kitCalibration"] as? [String: Any],
              Self.calibration(fromFirestore: rawCalibration) == calibration
        else {
            throw BoxReturnServiceError.roundTripFailed
        }

        if requestPickup {
            guard returned > 0 else { throw BoxReturnServiceError.invalidPickupCount }
            let result = try await functions.httpsCallable("requestConcierge")
                .call(Self.pickupPayload(userId: userId, returned: returned))
            guard let data = result.data as? [String: Any],
                  data["success"] as? Bool == true
            else {
                throw BoxReturnServiceError.pickupFailed
            }
        }

        return calibration
    }

    static func deliveredBoxCount(fromWorkflowResponse data: [String: Any]) -> Int? {
        guard let storedAnswers = data["answers"] as? [String: Any] else { return nil }
        let answers = storedAnswers["answers"] as? [String: Any] ?? storedAnswers
        guard let encodedKit = answers["kit"] as? [String],
              let first = encodedKit.first,
              let jsonData = first.data(using: .utf8),
              let kit = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        let boxKeys = ["small", "medium", "large", "wardrobe", "dishPack"]
        let counts = boxKeys.compactMap { (kit[$0] as? NSNumber)?.intValue }
        guard counts.count == boxKeys.count, counts.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        return counts.reduce(0, +)
    }

    static func calibration(fromFirestore data: [String: Any]) -> KitCalibration? {
        guard let delivered = (data["delivered"] as? NSNumber)?.intValue,
              let returned = (data["returned"] as? NSNumber)?.intValue,
              let ranOut = data["ranOut"] as? Bool,
              delivered >= 0,
              returned >= 0
        else { return nil }
        return KitCalibration(delivered: delivered, returned: returned, ranOut: ranOut)
    }

    static func pickupPayload(userId: String, returned: Int) -> [String: Any] {
        [
            "taskId": "BOX_RETURN",
            "taskTitle": "Pick up \(returned) returned boxes",
            "taskCategory": "packing",
            "userId": userId
        ]
    }
}

enum BoxReturnServiceError: LocalizedError {
    case missingUser
    case missingKitOrder
    case invalidReturnedCount
    case invalidPickupCount
    case roundTripFailed
    case pickupFailed

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "Sign in before saving your box count."
        case .missingKitOrder:
            return "Peezy couldn't find the packing kit you ordered."
        case .invalidReturnedCount:
            return "Enter a box count of zero or more."
        case .invalidPickupCount:
            return "Add at least one box before requesting pickup."
        case .roundTripFailed:
            return "Peezy couldn't verify that box count. Please try again."
        case .pickupFailed:
            return "Your count was saved, but the pickup request didn't go through. Please try again."
        }
    }
}
