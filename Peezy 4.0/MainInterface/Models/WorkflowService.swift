//
//  WorkflowService.swift
//  Peezy
//
//  Handles submitting workflow answers to Firebase
//

import Foundation
import FirebaseCrashlytics
import FirebaseFunctions

@Observable
class WorkflowService {
    private let functions = Functions.functions()

    // MARK: - Submit Answers

    func submitAnswers(
        workflowId: String,
        answers: WorkflowAnswers,
        userId: String
    ) async throws -> WorkflowSubmissionResponse {

        let callable = functions.httpsCallable("submitWorkflowAnswers")

        let payload: [String: Any] = [
            "workflowId": workflowId,
            "answers": answers.toDictionary(),
            "userId": userId
        ]

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
