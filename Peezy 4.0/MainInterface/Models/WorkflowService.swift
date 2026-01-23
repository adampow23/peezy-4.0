//
//  WorkflowService.swift
//  Peezy
//
//  Handles fetching workflow questions and submitting answers
//

import Foundation
import FirebaseFunctions

@Observable
class WorkflowService {
    private let functions = Functions.functions()

    // Cache qualifying data to avoid re-fetching
    private var cache: [String: WorkflowQualifying] = [:]

    // MARK: - Fetch Qualifying Questions

    func getQualifying(for workflowId: String) async throws -> WorkflowQualifying {
        // Check cache first
        if let cached = cache[workflowId] {
            return cached
        }

        // Call Firebase function
        let callable = functions.httpsCallable("getWorkflowQualifying")

        let result = try await callable.call(["workflowId": workflowId])

        guard let data = result.data as? [String: Any] else {
            throw WorkflowServiceError.invalidResponse
        }

        // Parse response
        let qualifying = try parseQualifying(from: data)

        // Cache it
        cache[workflowId] = qualifying

        return qualifying
    }

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

        let result = try await callable.call(payload)

        guard let data = result.data as? [String: Any] else {
            throw WorkflowServiceError.invalidResponse
        }

        return WorkflowSubmissionResponse(
            success: data["success"] as? Bool ?? false,
            submissionId: data["submissionId"] as? String ?? "",
            message: data["message"] as? String ?? "",
            estimatedResponseTime: data["estimatedResponseTime"] as? String ?? "24-48 hours"
        )
    }

    // MARK: - Clear Cache

    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Parsing

    private func parseQualifying(from data: [String: Any]) throws -> WorkflowQualifying {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let decoder = JSONDecoder()
        return try decoder.decode(WorkflowQualifying.self, from: jsonData)
    }
}

// MARK: - Errors

enum WorkflowServiceError: LocalizedError {
    case invalidResponse
    case noQuestionsFound
    case submissionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .noQuestionsFound:
            return "No qualifying questions found for this task"
        case .submissionFailed(let message):
            return "Failed to submit answers: \(message)"
        }
    }
}
