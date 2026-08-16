import Foundation
import FirebaseFunctions

nonisolated struct InventoryProcessingRequest: Equatable, Sendable {
    let userId: String
    let sessionId: String
    let roomName: String
    let frameCount: Int
}

@MainActor
protocol InventoryProcessingCalling {
    func processInventory(_ request: InventoryProcessingRequest) async throws
}

@MainActor
final class InventoryAPIClient: InventoryProcessingCalling {
    private let functions = Functions.functions()

    /// Trigger inventory processing for an uploaded session
    func processInventory(_ request: InventoryProcessingRequest) async throws {
        let data: [String: Any] = [
            "userId": request.userId,
            "sessionId": request.sessionId,
            "roomName": request.roomName,
            "frameCount": request.frameCount
        ]

        do {
            let result = try await functions.httpsCallable("processInventory").call(data)
            // Result contains {success: true, itemCount: N} but we don't need it —
            // the iOS app observes the Firestore document for the actual items
            if let response = result.data as? [String: Any],
               let success = response["success"] as? Bool, !success {
                throw InventoryError.processingFailed("Server returned success=false")
            }
        } catch let error as InventoryError {
            throw error
        } catch let error as NSError {
            if FunctionsErrorClassifier.classify(error) == .movePassRequired {
                throw InventoryError.movePassRequired
            }
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
    case movePassRequired
    case notAuthenticated
    case invalidRequest(String)
    case processingFailed(String)
    case networkError(Error)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .movePassRequired: return "Move Pass required"
        case .notAuthenticated: return "You must be signed in to scan inventory"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .processingFailed(let msg): return "Processing failed: \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        }
    }
}
