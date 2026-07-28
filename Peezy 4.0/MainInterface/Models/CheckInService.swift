import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct CheckInEstimatedRange: Equatable {
    let low: Double
    let high: Double
}

struct CheckInBookingContext {
    let vendorId: String
    let vendorName: String
    let estimatedRange: CheckInEstimatedRange
    let scopeSnapshot: [String: Any]
}

struct MoveCheckInAnswers: Equatable {
    let arrivedInWindow: Bool
    let crewWorkedSteadily: Bool
    let costMoreThanQuoted: Bool
    let damaged: Bool
    let note: String
    let finalBill: Double?

    var payload: [String: Any] {
        var data: [String: Any] = [
            "arrivedInWindow": arrivedInWindow,
            "crewWorkedSteadily": crewWorkedSteadily,
            "costMoreThanQuoted": costMoreThanQuoted,
            "damaged": damaged,
            "note": note.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        if let finalBill {
            data["finalBill"] = finalBill
        }
        return data
    }
}

struct CheckInSubmissionResponse: Equatable {
    let reviewId: String
    let calibrationId: String?
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
        return Self.bookingContext(fromWorkflowResponse: snapshot.data() ?? [:])
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
        let response = CheckInSubmissionResponse(
            reviewId: reviewId,
            calibrationId: data["calibrationId"] as? String,
            vendorId: data["vendorId"] as? String,
            flags: data["flags"] as? [String] ?? []
        )
        AnalyticsEvents.checkinCompleted(flagged: !response.flags.isEmpty)
        return response
    }

    static func bookingContext(fromWorkflowResponse data: [String: Any]) -> CheckInBookingContext? {
        guard let storedAnswers = data["answers"] as? [String: Any] else { return nil }
        let answers = storedAnswers["answers"] as? [String: Any] ?? storedAnswers

        func firstString(_ key: String) -> String? {
            (answers[key] as? [String])?.first
        }

        func object(_ key: String) -> [String: Any]? {
            guard let encoded = firstString(key),
                  let jsonData = encoded.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { return nil }
            return decoded
        }

        guard firstString("quoteRequest") == "false",
              let vendor = object("chosen_vendor"),
              let vendorId = (vendor["vendorId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !vendorId.isEmpty,
              let vendorName = (vendor["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !vendorName.isEmpty,
              let estimate = object("estimate"),
              let low = (estimate["low"] as? NSNumber)?.doubleValue,
              low.isFinite,
              low >= 0,
              let high = (estimate["high"] as? NSNumber)?.doubleValue,
              high.isFinite,
              high >= low,
              let scope = object("scope"),
              !scope.isEmpty,
              let cubicFeet = (scope["cubicFeet"] as? NSNumber)?.doubleValue,
              cubicFeet.isFinite,
              cubicFeet >= 0,
              let driveMinutes = (scope["driveMinutes"] as? NSNumber)?.doubleValue,
              driveMinutes.isFinite,
              driveMinutes >= 0
        else { return nil }

        return CheckInBookingContext(
            vendorId: vendorId,
            vendorName: vendorName,
            estimatedRange: CheckInEstimatedRange(low: low, high: high),
            scopeSnapshot: scope
        )
    }

    static func finalBill(from text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let amount = Double(normalized), amount.isFinite, amount > 0 else {
            return nil
        }
        return amount
    }
}

enum CheckInServiceError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "Peezy couldn't save that check-in. Please try again."
    }
}
