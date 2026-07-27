import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct CheckInBookingContext: Equatable {
    let vendorId: String
    let vendorName: String
}

struct MoveCheckInAnswers: Equatable {
    let arrivedInWindow: Bool
    let crewWorkedSteadily: Bool
    let costMoreThanQuoted: Bool
    let damaged: Bool
    let note: String

    var payload: [String: Any] {
        [
            "arrivedInWindow": arrivedInWindow,
            "crewWorkedSteadily": crewWorkedSteadily,
            "costMoreThanQuoted": costMoreThanQuoted,
            "damaged": damaged,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
    }
}

struct CheckInSubmissionResponse: Equatable {
    let reviewId: String
    let vendorId: String?
    let flags: [String]
}

struct CheckInService {
    private let db: Firestore
    private let functions: Functions

    init(
        db: Firestore = Firestore.firestore(),
        functions: Functions = Functions.functions()
    ) {
        self.db = db
        self.functions = functions
    }

    func loadBookingContext(userId: String) async throws -> CheckInBookingContext? {
        guard !userId.isEmpty else { return nil }
        let snapshot = try await db.collection("users").document(userId)
            .collection("workflowResponses").document("book_movers")
            .getDocument()
        guard let storedAnswers = snapshot.data()?["answers"] as? [String: Any] else {
            return nil
        }
        let answerMap = storedAnswers["answers"] as? [String: Any] ?? storedAnswers
        guard let encodedValues = answerMap["chosen_vendor"] as? [String],
              let encodedVendor = encodedValues.first,
              let data = encodedVendor.data(using: .utf8),
              let vendor = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vendorId = vendor["vendorId"] as? String,
              !vendorId.isEmpty,
              let vendorName = vendor["name"] as? String,
              !vendorName.isEmpty
        else { return nil }
        return CheckInBookingContext(vendorId: vendorId, vendorName: vendorName)
    }

    func submit(_ answers: MoveCheckInAnswers) async throws -> CheckInSubmissionResponse {
        let result = try await functions.httpsCallable("submitCheckIn").call([
            "answers": answers.payload
        ])
        guard let data = result.data as? [String: Any],
              data["success"] as? Bool == true,
              let reviewId = data["reviewId"] as? String
        else {
            throw CheckInServiceError.invalidResponse
        }
        return CheckInSubmissionResponse(
            reviewId: reviewId,
            vendorId: data["vendorId"] as? String,
            flags: data["flags"] as? [String] ?? []
        )
    }
}

enum CheckInServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Peezy couldn't save that check-in. Please try again."
    }
}
