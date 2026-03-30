import Foundation

enum WebhookService {
    // Hardcode for now — will move to config later
    static let webhookURL = "PLACEHOLDER_WEBHOOK_URL"

    static func sendTaskSubmission(
        userId: String,
        userName: String,
        taskId: String,
        taskTitle: String,
        taskType: String,
        confirmedFields: [String: String],
        transferChoice: String? = nil
    ) {
        guard let url = URL(string: webhookURL) else { return }

        var body: [String: Any] = [
            "userId": userId,
            "userName": userName,
            "taskId": taskId,
            "taskTitle": taskTitle,
            "taskType": taskType,
            "confirmedFields": confirmedFields,
            "submittedAt": ISO8601DateFormatter().string(from: Date())
        ]

        if let choice = transferChoice {
            body["transferChoice"] = choice
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Fire and forget — failure is silent, app flow continues
        URLSession.shared.dataTask(with: request).resume()
    }
}
