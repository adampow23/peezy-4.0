import Foundation

// MARK: - PeezyClient
/// Handles all network communication with the Peezy Firebase backend
final class PeezyClient {
    
    // MARK: - Configuration
    private let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    // Singleton for easy access
    static let shared = PeezyClient()
    
    // MARK: - Init
    init(
        baseURL: String = PeezyConfig.firebaseFunctionURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Main API Call
    
    /// Send a message to Peezy and get a response
    func sendMessage(
        _ message: String,
        userState: UserState,
        conversationHistory: [ChatMessage] = [],
        currentTaskId: String? = nil,
        requestType: String? = nil
    ) async throws -> PeezyResponse {
        
        let request = PeezyRequest(
            message: message,
            userState: userState,
            conversationHistory: conversationHistory,
            currentTaskId: currentTaskId,
            requestType: requestType
        )
        
        return try await post(endpoint: "peezyRespond", body: request)
    }
    
    /// Request initial cards for the stack (on app launch / refresh)
    func getInitialCards(userState: UserState) async throws -> PeezyResponse {
        return try await sendMessage(
            "",  // Empty message for initial load
            userState: userState,
            requestType: "initial_load"
        )
    }
    
    /// Notify backend of a card action (swipe)
    func recordCardAction(
        card: PeezyCard,
        action: SwipeAction,
        userState: UserState
    ) async throws -> PeezyResponse {
        
        let message: String
        switch action {
        case .doIt:
            message = "[ACTION] User approved: \(card.title)"
        case .later:
            message = "[ACTION] User deferred: \(card.title)"
        }
        
        return try await sendMessage(
            message,
            userState: userState,
            currentTaskId: card.taskId,
            requestType: "card_action"
        )
    }
    
    // MARK: - Network Layer
    
    private func post<T: Codable, R: Codable>(
        endpoint: String,
        body: T
    ) async throws -> R {
        
        // Build URL
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw PeezyError.invalidURL
        }
        
        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        // Encode body
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw PeezyError.encodingFailed(error)
        }
        
        // Log request in debug
        #if DEBUG
        logRequest(request, body: body)
        #endif
        
        // Make request
        let data: Data
        let response: URLResponse
        
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PeezyError.networkError(error)
        }
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PeezyError.invalidResponse
        }
        
        // Log response in debug
        #if DEBUG
        logResponse(httpResponse, data: data)
        #endif
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PeezyError.httpError(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }
        
        // Decode response
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw PeezyError.decodingFailed(error, body: String(data: data, encoding: .utf8))
        }
    }
    
    // MARK: - Debug Logging
    
    #if DEBUG
    private func logRequest<T: Codable>(_ request: URLRequest, body: T) {
        print("📤 PEEZY REQUEST")
        print("   URL: \(request.url?.absoluteString ?? "nil")")
        if let bodyData = try? encoder.encode(body),
           let bodyString = String(data: bodyData, encoding: .utf8) {
            // Truncate long bodies
            let truncated = bodyString.prefix(500)
            print("   Body: \(truncated)\(bodyString.count > 500 ? "..." : "")")
        }
    }
    
    private func logResponse(_ response: HTTPURLResponse, data: Data) {
        let emoji = (200...299).contains(response.statusCode) ? "✅" : "❌"
        print("\(emoji) PEEZY RESPONSE [\(response.statusCode)]")
        if let bodyString = String(data: data, encoding: .utf8) {
            let truncated = bodyString.prefix(500)
            print("   Body: \(truncated)\(bodyString.count > 500 ? "..." : "")")
        }
    }
    #endif
}

// MARK: - Configuration
enum PeezyConfig {
    static let firebaseFunctionURL = "https://us-central1-peezy-1ecrdl.cloudfunctions.net"
    
    // For local testing with Firebase emulator
    static let localEmulatorURL = "http://localhost:5001/peezy-1ecrdl/us-central1"
}

// MARK: - Errors
enum PeezyError: LocalizedError {
    case invalidURL
    case encodingFailed(Error)
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(Error, body: String?)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL configuration"
        case .encodingFailed(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let body):
            return "HTTP error \(statusCode): \(body ?? "No body")"
        case .decodingFailed(let error, let body):
            return "Failed to decode response: \(error.localizedDescription). Body: \(body ?? "nil")"
        }
    }
}
