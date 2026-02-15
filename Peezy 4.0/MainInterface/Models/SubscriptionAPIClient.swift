//
//  SubscriptionAPIClient.swift
//  Peezy
//
//  Thin client for sending subscription transaction data to the
//  Firebase Cloud Function for server-side record-keeping.
//  Used as fire-and-forget from SubscriptionManager.
//

import Foundation

enum SubscriptionAPIClient {

    static func validateReceipt(payload: [String: Any]) async throws {
        let urlString = "\(PeezyConfig.firebaseFunctionURL)/validateSubscription"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
