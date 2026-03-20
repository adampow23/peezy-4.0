import Foundation
import FirebaseFunctions

final class InventoryAPIClient {
    private let functions = Functions.functions()

    /// Trigger inventory processing for an uploaded session
    func processInventory(
        userId: String,
        sessionId: String,
        roomName: String,
        frameCount: Int
    ) async throws {
        let data: [String: Any] = [
            "userId": userId,
            "sessionId": sessionId,
            "roomName": roomName,
            "frameCount": frameCount
        ]

        do {
            let result = try await functions.httpsCallable("processInventory").call(data)
            // Result contains {success: true, itemCount: N} but we don't need it —
            // the iOS app observes the Firestore document for the actual items
            if let response = result.data as? [String: Any],
               let success = response["success"] as? Bool, !success {
                throw InventoryError.processingFailed("Server returned success=false")
            }
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw InventoryError.notAuthenticated
                case .invalidArgument:
                    throw InventoryError.invalidRequest(error.localizedDescription)
                default:
                    throw InventoryError.processingFailed(error.localizedDescription)
                }
            }
            throw InventoryError.networkError(error)
        }
    }

    /// Trigger admin inventory package email after user saves
    func packageInventory() async throws {
        do {
            let result = try await functions.httpsCallable("packageInventory").call([:])
            if let response = result.data as? [String: Any],
               let success = response["success"] as? Bool, !success {
                throw InventoryError.processingFailed("Package send returned success=false")
            }
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                throw InventoryError.processingFailed(error.localizedDescription)
            }
            throw InventoryError.networkError(error)
        }
    }
}

enum InventoryError: LocalizedError {
    case notAuthenticated
    case invalidRequest(String)
    case processingFailed(String)
    case networkError(Error)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to scan inventory"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .processingFailed(let msg): return "Processing failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        }
    }
}
