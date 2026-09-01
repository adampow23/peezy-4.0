//
//  WorkflowService.swift
//  Peezy
//
//  Handles submitting workflow answers to Firebase
//

import Foundation
import CryptoKit
import FirebaseCrashlytics
import FirebaseFunctions

/// Stable logical-submission identity. Length-prefixing makes the unhashed
/// tuple unambiguous; SHA-256 keeps the callable token bounded even when an
/// upstream identifier is unexpectedly large. The backend scopes and hashes
/// this value again before persistence.
nonisolated enum WorkflowSubmissionToken {
    static func make(
        userId: String,
        taskId: String,
        workflowId: String,
        flowAttemptId: String
    ) -> String {
        let components = [userId, taskId, workflowId, flowAttemptId]
        let canonical = components
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "workflow-v1-\(digest)"
    }
}

@Observable
class WorkflowService {
    private let functions = Functions.functions()

    // MARK: - Submit Answers

    func submitAnswers(
        workflowId: String,
        answers: WorkflowAnswers,
        userId: String,
        submissionToken: String? = nil
    ) async throws -> WorkflowSubmissionResponse {

        let callable = functions.httpsCallable("submitWorkflowAnswers")

        let payload = Self.makePayload(
            workflowId: workflowId,
            answers: answers,
            userId: userId,
            submissionToken: submissionToken
        )

        do {
            let result = try await callable.call(payload)

            guard let data = result.data as? [String: Any] else {
                throw WorkflowServiceError.invalidResponse
            }

            let response = WorkflowSubmissionResponse(
                success: data["success"] as? Bool ?? false,
                submissionId: data["submissionId"] as? String ?? "",
                message: data["message"] as? String ?? "",
                estimatedResponseTime: data["estimatedResponseTime"] as? String ?? "24-48 hours"
            )
            if response.success {
                recordBookingSubmission(workflowId: workflowId, answers: answers)
            }
            return response
        } catch {
            Crashlytics.crashlytics().record(error: error)
            throw error
        }
    }

    static func makePayload(
        workflowId: String,
        answers: WorkflowAnswers,
        userId: String,
        submissionToken: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "workflowId": workflowId,
            "answers": answers.toDictionary(),
            "userId": userId
        ]
        if let submissionToken {
            payload["submissionToken"] = submissionToken
        }
        return payload
    }

    private func recordBookingSubmission(
        workflowId: String,
        answers: WorkflowAnswers
    ) {
        switch workflowId {
        case "book_movers":
            AnalyticsEvents.bookingSubmitted(
                vertical: "movers",
                isQuoteRequest: answers.answers["quoteRequest"]?.first == "true"
            )
        case "book_cleaners":
            AnalyticsEvents.bookingSubmitted(vertical: "cleaners", isQuoteRequest: true)
        default:
            break
        }
    }
}

// MARK: - Errors

enum WorkflowServiceError: LocalizedError {
    case invalidResponse
    case submissionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .submissionFailed(let message):
            return "Failed to submit answers: \(message)"
        }
    }
}
