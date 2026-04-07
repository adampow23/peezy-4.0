import Foundation
import FirebaseFunctions

enum WebhookService {

    /// Sends task flow submission to the backend via Cloud Function.
    /// Called when user confirms details on a research or transfer/cancel task.
    /// Fire-and-forget — failure is silent, app flow continues regardless.
    static func sendTaskSubmission(
        userId: String,
        userName: String,
        taskId: String,
        taskTitle: String,
        taskType: String,
        confirmedFields: [String: String],
        transferChoice: String? = nil
    ) {
        let callable = Functions.functions().httpsCallable("submitTaskFlow")

        var payload: [String: Any] = [
            "userId": userId,
            "userName": userName,
            "taskId": taskId,
            "taskTitle": taskTitle,
            "taskType": taskType,
            "confirmedFields": confirmedFields
        ]

        if let choice = transferChoice {
            payload["transferChoice"] = choice
        }

        // Fire and forget — failure is silent, app flow continues
        Task {
            do {
                _ = try await callable.call(payload)
            } catch {
                print("Task flow submission failed: \(error.localizedDescription)")
            }
        }
    }
}
